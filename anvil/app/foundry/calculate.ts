const operators = /[+\-*/×÷x^%]/;

function format(value: number): string {
  const size = Math.abs(value);
  if (size >= 1e15 || (size > 0 && size < 1e-6)) return Number(value.toPrecision(12)).toExponential();
  return (value + 0).toLocaleString("en-US", { maximumSignificantDigits: 12 });
}

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
    const match = /^\d*\.?\d+/.exec(source.slice(index));
    if (!match) throw new Error();
    index += match[0].length;
    let value = Number(match[0]);
    if (peek() === "%") { index++; value /= 100; }
    return value;
  }
  function power(): number {
    if (peek() === "-") { index++; return -power(); }
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
    while (peek() === "+" || peek() === "-") {
      const sign = source[index++] === "+" ? 1 : -1;
      const start = index;
      const term = product();
      value += sign * (/^\d*\.?\d+%$/.test(source.slice(start, index)) ? value * term : term);
    }
    return value;
  }
  try {
    const value = sum();
    if (index !== source.length || !Number.isFinite(value)) return null;
    return format(value);
  } catch {
    return null;
  }
}
