import { readFile } from "node:fs/promises";
import { parentPort, workerData } from "node:worker_threads";

if (parentPort === null) throw new Error("worker parent port is unavailable");

const wasmBytes = await readFile(new URL("./calculator.wasm", import.meta.url));
const { instance } = await WebAssembly.instantiate(wasmBytes);
parentPort.postMessage(instance.exports.add(workerData.left, workerData.right));
