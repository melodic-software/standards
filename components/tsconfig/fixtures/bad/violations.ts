function build(name) {
  const labels: string[] = ["a", "b"];
  return `${name}: ${labels[0].toUpperCase()}`;
}

build("x");
