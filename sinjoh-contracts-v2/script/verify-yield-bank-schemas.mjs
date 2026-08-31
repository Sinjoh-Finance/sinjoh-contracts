import { readFile } from "node:fs/promises";

const schemaPaths = [
  new URL("../deployments/yield-banks-deployment-plan.schema.json", import.meta.url),
  new URL("../deployments/yield-banks-manifest.schema.json", import.meta.url),
];

function resolveJsonPointer(document, reference) {
  if (!reference.startsWith("#/")) {
    throw new Error(`external schema reference is not pinned locally: ${reference}`);
  }
  return reference.slice(2).split("/").reduce((value, segment) => {
    const key = segment.replaceAll("~1", "/").replaceAll("~0", "~");
    if (value === null || typeof value !== "object" || !(key in value)) {
      throw new Error(`unresolved schema reference: ${reference}`);
    }
    return value[key];
  }, document);
}

function verifyReferences(document, value = document) {
  if (Array.isArray(value)) {
    for (const item of value) verifyReferences(document, item);
    return;
  }
  if (value === null || typeof value !== "object") return;
  if (typeof value.$ref === "string") resolveJsonPointer(document, value.$ref);
  for (const child of Object.values(value)) verifyReferences(document, child);
}

for (const schemaPath of schemaPaths) {
  const schema = JSON.parse(await readFile(schemaPath, "utf8"));
  if (schema.$schema !== "https://json-schema.org/draft/2020-12/schema") {
    throw new Error(`${schemaPath.pathname} must pin JSON Schema draft 2020-12`);
  }
  if (typeof schema.$id !== "string" || !schema.$id.startsWith("https://sinjoh.com/schemas/")) {
    throw new Error(`${schemaPath.pathname} must use a canonical Sinjoh schema id`);
  }
  verifyReferences(schema);
  console.log(`${schemaPath.pathname}: all local schema references resolve`);
}
