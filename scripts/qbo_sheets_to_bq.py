#!/usr/bin/env python3
"""Load QBO data from Google Sheets (Coupler.io) into BigQuery staging tables.

Reads the "ExampleCo QBO" spreadsheet using workspace MCP OAuth credentials,
then loads each sheet tab into the corresponding BQ staging_ext table.

Usage:
    python3 qbo_sheets_to_bq.py [--sheet SHEET_NAME]

    Without --sheet, loads all sheets.
"""

import json
import sys
import argparse
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from google.cloud import bigquery

SPREADSHEET_ID = "1AFGtNcqZj5VA5Lm8HFZxmB-V7EyIKzEYtZ2AfIeuRjc"
CREDS_FILE = "/home/kenji/.google_workspace_mcp/credentials/user@client.example.com.json"
BQ_PROJECT = "example-project"
BQ_DATASET = "staging_ext"

# Map sheet tab names to BQ table names
SHEET_TO_TABLE = {
    "Sheet1": "qbo_invoices",
    "Customer": "qbo_customers",
    "Payment": "qbo_payments",
    "Bill": "qbo_bills",
    "Vendor": "qbo_vendors",
    "Account": "qbo_accounts",
    "Purchase": "qbo_purchases",
    "JournalEntry": "qbo_journal_entries",
}


def get_sheets_credentials():
    with open(CREDS_FILE) as f:
        token_data = json.load(f)

    # Get OAuth client info from the workspace MCP credentials.json
    creds_json_path = "/home/kenji/.google_workspace_mcp/credentials.json"
    with open(creds_json_path) as f:
        client_config = json.load(f)

    installed = client_config.get("installed", client_config.get("web", {}))
    client_id = installed["client_id"]
    client_secret = installed["client_secret"]
    token_uri = installed.get("token_uri", "https://oauth2.googleapis.com/token")

    creds = Credentials(
        token=token_data["token"],
        refresh_token=token_data["refresh_token"],
        token_uri=token_uri,
        client_id=client_id,
        client_secret=client_secret,
        scopes=token_data.get("scopes", []),
    )
    return creds


def read_sheet(service, sheet_name):
    result = (
        service.spreadsheets()
        .values()
        .get(spreadsheetId=SPREADSHEET_ID, range=f"{sheet_name}!A1:ZZ")
        .execute()
    )
    values = result.get("values", [])
    if not values:
        return None, None

    headers = values[0]
    rows = values[1:]
    return headers, rows


def sanitize_column_name(name):
    """Convert a Sheets column name to a valid BQ column name."""
    name = name.replace(".", "_").replace(" ", "_").replace("-", "_")
    name = name.replace("(", "").replace(")", "").replace("/", "_")
    # Remove any remaining non-alphanumeric chars (except underscore)
    clean = ""
    for c in name:
        if c.isalnum() or c == "_":
            clean += c
    # BQ column names can't start with a number
    if clean and clean[0].isdigit():
        clean = "_" + clean
    return clean


def load_to_bq(table_name, headers, rows):
    client = bigquery.Client(project=BQ_PROJECT)
    table_id = f"{BQ_PROJECT}.{BQ_DATASET}.{table_name}"

    # Sanitize column names
    clean_headers = [sanitize_column_name(h) for h in headers]

    # Build rows as dicts
    json_rows = []
    for row in rows:
        record = {}
        for i, header in enumerate(clean_headers):
            if i < len(row) and row[i] != "":
                record[header] = row[i]
            else:
                record[header] = None
        json_rows.append(record)

    if not json_rows:
        print(f"  No data rows for {table_name}, skipping")
        return

    # Auto-detect schema from the data
    schema = []
    for header in clean_headers:
        schema.append(bigquery.SchemaField(header, "STRING", mode="NULLABLE"))

    # Configure the load job
    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
    )

    # Load data
    import io
    import ndjson

    json_str = ndjson.dumps(json_rows)
    json_bytes = json_str.encode("utf-8")
    source = io.BytesIO(json_bytes)

    job = client.load_table_from_file(source, table_id, job_config=job_config)
    job.result()  # Wait for completion

    table = client.get_table(table_id)
    print(f"  Loaded {table.num_rows} rows into {table_id}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sheet", help="Load only this sheet tab name")
    args = parser.parse_args()

    print("Authenticating with Google Sheets...")
    creds = get_sheets_credentials()
    service = build("sheets", "v4", credentials=creds)

    sheets_to_load = SHEET_TO_TABLE
    if args.sheet:
        if args.sheet not in SHEET_TO_TABLE:
            print(f"Unknown sheet: {args.sheet}. Valid: {list(SHEET_TO_TABLE.keys())}")
            sys.exit(1)
        sheets_to_load = {args.sheet: SHEET_TO_TABLE[args.sheet]}

    for sheet_name, table_name in sheets_to_load.items():
        print(f"\nProcessing {sheet_name} -> {table_name}...")
        headers, rows = read_sheet(service, sheet_name)
        if headers is None:
            print(f"  Sheet '{sheet_name}' is empty, skipping")
            continue
        print(f"  Read {len(rows)} rows, {len(headers)} columns")
        load_to_bq(table_name, headers, rows)

    print("\nDone!")


if __name__ == "__main__":
    main()
