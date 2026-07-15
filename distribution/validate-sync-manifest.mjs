import { readFile } from "node:fs/promises";
import process from "node:process";

import Ajv2020 from "ajv/dist/2020.js";

const schemaPath = new URL("./sync-manifest.schema.json", import.meta.url);
const schema = JSON.parse(await readFile(schemaPath, "utf8"));
const source = await new Promise((resolve, reject) => {
  let value = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => {
    value += chunk;
  });
  process.stdin.on("end", () => resolve(value));
  process.stdin.on("error", reject);
});

let manifest;
try {
  manifest = JSON.parse(source);
} catch (error) {
  process.stderr.write(`error: manifest JSON conversion is invalid: ${error.message}\n`);
  process.exitCode = 1;
}

if (manifest !== undefined) {
  const ajv = new Ajv2020({ allErrors: false, strict: true, validateFormats: false });
  const validate = ajv.compile(schema);
  if (!validate(manifest)) {
    const [error] = validate.errors;
    let location = `manifest${error.instancePath
      .split("/")
      .slice(1)
      .map((segment) => `.${segment.replaceAll("~1", "/").replaceAll("~0", "~")}`)
      .join("")}`;
    if (error.keyword === "additionalProperties") {
      location += `.${error.params.additionalProperty}`;
    } else if (error.keyword === "propertyNames") {
      location += `.${error.params.propertyName}`;
    }
    const message =
      error.keyword === "const"
        ? `must equal ${JSON.stringify(error.params.allowedValue)}`
        : error.keyword === "additionalProperties"
          ? "is not allowed"
          : error.message;
    process.stderr.write(`error: ${location} ${message}\n`);
    process.exitCode = 1;
  }
}
