import { readFile } from "node:fs/promises";
import { Worker } from "node:worker_threads";

export async function check(left, right) {
  const wasmBytes = await readFile(new URL("./calculator.wasm", import.meta.url));
  const { instance } = await WebAssembly.instantiate(wasmBytes);
  const direct = instance.exports.add(left, right);
  const worker = new Worker(new URL("./worker.mjs", import.meta.url), {
    workerData: { left, right },
  });

  let received = false;
  try {
    const workerResult = await new Promise((resolve, reject) => {
      worker.once("message", (value) => {
        received = true;
        resolve(value);
      });
      worker.once("error", reject);
      worker.once("exit", (code) => {
        if (!received) reject(new Error(`worker exited before replying (code ${code})`));
      });
    });
    return { direct, worker: workerResult };
  } finally {
    await worker.terminate();
  }
}
