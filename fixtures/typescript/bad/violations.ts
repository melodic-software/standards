function build(name) {
  const labels: string[] = ["a", "b"];
  console.log(name, labels[0].toUpperCase());
}

export function run(): void {
  build("x");
  fetchData();
}

async function fetchData(): Promise<number> {
  return 42;
}
