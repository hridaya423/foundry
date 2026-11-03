const operators = /[+\-*/×÷x^%]/;

export function calculate(input: string): string | null {
  const source = input.replace(/\s+/g, "").replace(/[×x]/g, "*").replace(/÷/g, "/");
  if (!/^[\d.+\-*/^%()]+$/.test(source) || !operators.test(source.slice(1))) return null;
  let index = 0;
  const peek = () => source[index];
  function number(): number {
    if (peek() === "(") {
      index++;
      const value = sum();
      if (peek() !== ")") throw new Error();
      index++;
      return value;
    }
    if (peek() === "-") { index++; return -number(); }
    const match = /^\d*\.?\d+/.exec(source.slice(index));
    if (!match) throw new Error();
    index += match[0].length;
    let value = Number(match[0]);
    if (peek() === "%") { index++; value /= 100; }
    return value;
  }
  function power(): number {
    const base = number();
    if (peek() !== "^") return base;
    index++;
    return base ** power();
  }
  function product(): number {
    let value = power();
    while (peek() === "*" || peek() === "/") value = source[index++] === "*" ? value * power() : value / power();
    return value;
  }
  function sum(): number {
    let value = product();
    while (peek() === "+" || peek() === "-") value = source[index++] === "+" ? value + product() : value - product();
    return value;
  }
  try {
    const value = sum();
    if (index !== source.length || !Number.isFinite(value)) return null;
    return value.toLocaleString("en-US", { maximumFractionDigits: 8 });
  } catch {
    return null;
  }
}
