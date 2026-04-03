import esbuild from 'esbuild';

const watch = process.argv.includes('--watch');

const ctx = await esbuild.context({
  entryPoints: ['src/app.js'],
  bundle: true,
  outdir: 'dist',
  format: 'esm',
  platform: 'browser',
  loader: { '.css': 'css' },
  minify: !watch,
  sourcemap: watch,
  logLevel: 'info',
});

if (watch) {
  await ctx.watch();
  console.log('watching for changes...');
} else {
  await ctx.rebuild();
  await ctx.dispose();
}
