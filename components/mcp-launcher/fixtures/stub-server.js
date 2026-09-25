// Test double for an MCP stdio server: echoes stdin to stdout, reports on
// stderr whether each named variable reached it, and exits with argv[2].
const [code, ...names] = process.argv.slice(2);
for (const name of names) {
  process.stderr.write(`stub-server: ${name}=${process.env[name] ?? "<unset>"}\n`);
}
process.stdin.pipe(process.stdout);
process.stdin.on("end", () => {
  process.exitCode = Number(code);
});
