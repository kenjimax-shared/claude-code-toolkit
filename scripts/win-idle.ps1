Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WinIdle {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static int Seconds() {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref info);
        return (int)((uint)Environment.TickCount - info.dwTime) / 1000;
    }
}
"@
[WinIdle]::Seconds()
