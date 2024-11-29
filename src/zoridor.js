let globalInstance = null;
let console_buffer = '';

function console_write(dataPtr, len) {
    const wasmMemoryArray = new Uint8Array(globalInstance.exports.memory.buffer);
    var arr = new Uint8Array(wasmMemoryArray.buffer, dataPtr, len);
    let string = new TextDecoder().decode(arr);

    console_buffer += string.toString('binary');

    // force output of very long line
    if (console_buffer.length > 1024) {
        console.log(console_buffer);
        console_buffer = '';
    }

    // break on lines
    let lines = console_buffer.split(/\r?\n/);
    if (lines.length > 1) {
        console_buffer = lines.pop();
        lines.forEach(l => console.log(l));
    }
}

function getTimeUs() {
    return window.performance.now() * 1000;
}

export class Zoridor {
    static getInstance() {
        return globalInstance;
    }

    static async init(wasmFile, sampleRate) {
        // fetch wasm and instantiate
        await fetch(wasmFile).then((response) => {
            return response.arrayBuffer();
        }).then((bytes) => {
            let imports = {
                env: {
                    console_write: console_write,
                    getTimeUs: getTimeUs
                }
            };
            return WebAssembly.instantiate(bytes, imports);
        }).then((results) => {
            let instance = results.instance;
            console.log("Instantiated wasm", instance.exports);
            globalInstance = instance;
        }).catch((err) => {
            console.log(err);
        });
    }

    static async start() {
        // tell wasm to start
        if (globalInstance.exports.init) {
            globalInstance.exports.init();
            console.log(globalInstance.exports.getNextMove());
            console.log(globalInstance.exports.getNextMove());
        }
    }
}
