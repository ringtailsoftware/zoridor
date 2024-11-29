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
    static colourBackground = 'rgb(175,138,100)';
    static colourPawnSquareEmpty = 'rgb(101,67,40)'; 
    static colourFence = 'rgb(229,203,67)';
    static colourFenceIllegal = null;
    static fenceRadius = '5px';
    static pawnRadius = '50px';
    static colourPawns = [
        'rgb(25,25,25)',
        'rgb(215,30,40)'
    ];
    static colourPawnsDim = [
        'rgb(80,60,35)',
        'rgb(80,60,35)'
    ];

    static colourPawnIllegal = null;

    static HORZ = 'h'.charCodeAt(0);
    static VERT = 'v'.charCodeAt(0);

    static gameOver = false;
    static fences = [];
    static pawns = [];
    static pi = 0;  // which player's turn

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
            this.fetchState();
            this.drawPieces();
        }
    }

    static decodePos(x, y) {
        let gx = Math.floor(x/3);    // game coords
        let gy = Math.floor(y/3);

        if ((x % 3 == 0 || x % 3 == 1) && (y % 3 == 0 || y % 3 == 1)) { // in a pawn area
            return {pawn: {x: gx, y: gy}};
        }

        if ((x % 3 == 2) && (y % 3 == 0 || y % 3 == 1)) { // vert fence
            if (gy > 7) {
                gy = 7;
            }
            // try the other half of the fence
            if (!globalInstance.exports.isFenceMoveLegal(gx, gy, this.VERT) && gy > 0) {
                gy -= 1;
            }
            return {fence: {x: gx, y: gy, dir: this.VERT}};
        }

        if ((y % 3 == 2) && (x % 3 == 0 || x % 3 == 1)) { // horz fence
            if (gx > 7) {
                gx = 7;
            }
            // try the other half of the fence
            if (!globalInstance.exports.isFenceMoveLegal(gx, gy, this.HORZ) && gx > 0) {
                gx -= 1;
            }
            return {fence: {x: gx, y: gy, dir: this.HORZ}};
        }
       
        // dead centre spot, move left giving horizontal fence
        return this.decodePos(x-1, y);
    }

    static click(x, y) {
        if (this.gameOver) {
            return;
        }
        const p = this.decodePos(x, y);
        if (p) {
            if (p.pawn) {
                if (globalInstance.exports.isPawnMoveLegal(p.pawn.x, p.pawn.y)) {
                    globalInstance.exports.movePawn(p.pawn.x, p.pawn.y);
                    this.fetchState();
                    this.drawPieces();
                }
            }
            if (p.fence) {
                if (globalInstance.exports.isFenceMoveLegal(p.fence.x, p.fence.y, p.fence.dir)) {
                    globalInstance.exports.moveFence(p.fence.x, p.fence.y, p.fence.dir);
                    this.fetchState();
                    this.drawPieces();
                }
            }
        }
    }

    static mouseOver(x, y) {
        if (this.gameOver) {
            return;
        }
        const p = this.decodePos(x, y);
        if (p) {
            if (p.pawn) {
                //console.log(`P ${p.pawn.x},${p.pawn.y} (${x},${y})`);
                if (globalInstance.exports.isPawnMoveLegal(p.pawn.x, p.pawn.y)) {
                    this.drawPawn(this.pawns[this.pi].x, this.pawns[this.pi].y, this.colourPawnsDim[this.pi], 0);   // old pos
                    this.drawPawn(p.pawn.x, p.pawn.y, this.colourPawns[this.pi], this.pawnRadius);  // new pos
                } else {
                    this.drawPawn(p.pawn.x, p.pawn.y, this.colourPawnIllegal, 0);
                }
            }
            if (p.fence) {
                //console.log(`F ${p.fence.x},${p.fence.y},${p.fence.dir} (${x},${y})`);
                if (globalInstance.exports.isFenceMoveLegal(p.fence.x, p.fence.y, p.fence.dir)) {
                    this.drawFence(p.fence.x, p.fence.y, p.fence.dir, this.colourFence);
                } else {
                    this.drawFence(p.fence.x, p.fence.y, p.fence.dir, this.colourFenceIllegal);
                }
            }
        }
    }

    static mouseOut(x, y) {
        if (this.gameOver) {
            return;
        }
        this.drawPieces();
    }

    static drawFence(fx, fy, dir, col) {
        if (!col) {
            return;
        }

        if (dir == this.VERT) {
            for (let y=0;y<5;y++) {
                let td = document.getElementById(`cell${fx*3+2},${fy*3+y}`);
                td.style['background-color'] = col;
                if (y == 0) {
                    td.style['border-top-left-radius'] = this.fenceRadius;
                    td.style['border-top-right-radius'] = this.fenceRadius;
                }
                if (y == 4) {
                    td.style['border-bottom-left-radius'] = this.fenceRadius;
                    td.style['border-bottom-right-radius'] = this.fenceRadius;
                }

            }
        } else {
            for (let x=0;x<5;x++) {
                let td = document.getElementById(`cell${fx*3+x},${fy*3+2}`);
                td.style['background-color'] = col;
                if (x == 0) {
                    td.style['border-top-left-radius'] = this.fenceRadius;
                    td.style['border-bottom-left-radius'] = this.fenceRadius;
                }
                if (x == 4) {
                    td.style['border-top-right-radius'] = this.fenceRadius;
                    td.style['border-bottom-right-radius'] = this.fenceRadius;
                }
            }
        }
    }

    static drawPawn(x, y, col, radius) {
        if (!col) {
            return;
        }
        let td = document.getElementById(`cell${x*3},${y*3}`);
        td.style['border-top-left-radius'] = radius;
        td.style['background-color'] = col;
        td = document.getElementById(`cell${x*3+1},${y*3}`);
        td.style['border-top-right-radius'] = radius;
        td.style['background-color'] = col;
        td = document.getElementById(`cell${x*3},${y*3+1}`);
        td.style['border-bottom-left-radius'] = radius;
        td.style['background-color'] = col;
        td = document.getElementById(`cell${x*3+1},${y*3+1}`);
        td.style['border-bottom-right-radius'] = radius;
        td.style['background-color'] = col;
    }

    static drawPieces() {
        
        const pawnSz = 2;
        const fenceSz = 1;
        const dim = pawnSz*9 + fenceSz*8;

        // all cells in background colour
        for (let y=0;y<dim;y++) {
            for (let x=0;x<dim;x++) {
                let td = document.getElementById(`cell${x},${y}`);
                td.style['background-color'] = this.colourBackground;
                td.style['border-top-right-radius'] = '0px';
                td.style['border-top-left-radius'] = '0px';
                td.style['border-bottom-right-radius'] = '0px';
                td.style['border-bottom-left-radius'] = '0px';
            }
        }

        // pawn spots
        for (let y=0;y<9;y++) {
            for (let x=0;x<9;x++) {
                let td = document.getElementById(`cell${x*3},${y*3}`);
                td.style['background-color'] = this.colourPawnSquareEmpty;
                td = document.getElementById(`cell${x*3+1},${y*3}`);
                td.style['background-color'] = this.colourPawnSquareEmpty;
                td = document.getElementById(`cell${x*3},${y*3+1}`);
                td.style['background-color'] = this.colourPawnSquareEmpty;
                td = document.getElementById(`cell${x*3+1},${y*3+1}`);
                td.style['background-color'] = this.colourPawnSquareEmpty;
            }
        }

        this.fences.forEach((f) => {
            this.drawFence(f.x, f.y, f.dir, this.colourFence);
        });

        for (let i=0;i<this.pawns.length;i++) {
            const p = this.pawns[i];
            this.drawPawn(p.x, p.y, this.colourPawns[i], this.pawnRadius);
        }
    }

    static fetchState() {
        this.pawns[0] = {
            x: globalInstance.exports.getPawnPosX(0),
            y: globalInstance.exports.getPawnPosY(0)
        };
        this.pawns[1] = {
            x: globalInstance.exports.getPawnPosX(1),
            y: globalInstance.exports.getPawnPosY(1)
        };
        for (let i=0;i<globalInstance.exports.getNumFences();i++) {
            this.fences[i] = {
                x: globalInstance.exports.getFencePosX(i),
                y: globalInstance.exports.getFencePosY(i),
                dir: globalInstance.exports.getFencePosDir(i),
            };
        }
        this.pi = globalInstance.exports.getPlayerIndex();
        if (globalInstance.exports.hasWon(0)) {
            this.gameOver = true;
        }
        if (globalInstance.exports.hasWon(1)) {
            this.gameOver = true;
        }

        //console.log(this.fences);
    }

    static tableCreate() {
        let body = document.body;
        let tbl = document.createElement('table');
        tbl.style.width = '600px';
        tbl.style.height = '600px';
        tbl.style.border = '30px ridge ' + this.colourBackground;
        tbl.style['border-spacing'] = '0px';
        tbl.style['background-color'] = this.colourBackground;

        const pawnSz = 2;
        const fenceSz = 1;
        const dim = pawnSz*9 + fenceSz*8;

        for (let y=0;y<dim;y++) {
            const tr = tbl.insertRow();
            for (let x=0;x<dim;x++) {
                const td = tr.insertCell();

                td.appendChild(document.createTextNode(""));
                td.style['background-color'] = this.colourBackground;
                td.style.transition = '0.1s';
                td.id = `cell${x},${y}`

                td.onmouseover = (evt) => {
                    this.mouseOver(x, y);
                };
                td.onmouseout = (evt) => {
                    this.mouseOut(x, y);
                };
                td.onclick = (evt) => {
                    this.click(x, y);
                };

            }
        }

        body.appendChild(tbl);

        this.drawPieces();
    }

}
