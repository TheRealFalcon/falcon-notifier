// Exercise the compiled client against a tiny local WebSocket fixture (Node standard library only).
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { once } from 'node:events';

const server = createServer();
const sockets = new Set();
let connectionCount = 0;
let activeSocket;
let child;
let phase = 0;
const timeout = setTimeout(() => { console.error('Integration test timed out'); cleanup(); process.exitCode = 1; }, 45000);

function cleanup() {
    clearTimeout(timeout);
    child?.kill();
    for (const socket of sockets) socket.destroy();
    server.close();
}

function send(socket, message) {
    const body = Buffer.from(JSON.stringify(message));
    const header = Buffer.alloc(body.length < 126 ? 2 : 4);
    header[0] = 0x81;
    if (body.length < 126) header[1] = body.length;
    else { header[1] = 126; header.writeUInt16BE(body.length, 2); }
    socket.write(Buffer.concat([header, body]));
}

function status(id, type, activeFlags = []) {
    send(activeSocket, { method: 'thread/status/changed', params: { threadId: id, status: { type, activeFlags } } });
}

server.on('upgrade', (request, socket, head) => {
    const connection = ++connectionCount;
    activeSocket = socket;
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => {});
    const accept = createHash('sha1').update(request.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    let buffer = head;
    socket.on('data', chunk => {
        buffer = Buffer.concat([buffer, chunk]);
        while (buffer.length >= 2) {
            const opcode = buffer[0] & 15;
            let length = buffer[1] & 127;
            let offset = 2;
            if (length === 126) {
                if (buffer.length < 4) return;
                length = buffer.readUInt16BE(2); offset = 4;
            }
            assert.notEqual(length, 127, 'fixture expects small client messages');
            assert.ok(buffer[1] & 128, 'client frames must be masked');
            if (buffer.length < offset + 4 + length) return;
            const mask = buffer.subarray(offset, offset + 4);
            const body = Buffer.from(buffer.subarray(offset + 4, offset + 4 + length));
            for (let i = 0; i < body.length; i++) body[i] ^= mask[i % 4];
            buffer = buffer.subarray(offset + 4 + length);
            if (opcode === 8) { socket.end(); return; }
            assert.equal(opcode, 1, 'requests use text frames');
            const message = JSON.parse(body);
            assert.ok(['initialize', 'initialized', 'thread/loaded/list', 'thread/read'].includes(message.method),
                'observer must not answer approvals or mutate sessions');
            const respond = result => send(socket, { id: message.id, result });
            switch (message.method) {
                case 'initialize': respond({}); break;
                case 'initialized': break;
                case 'thread/loaded/list':
                    if (connection > 1 || phase > 0) respond({ data: [], nextCursor: null });
                    else if (!message.params.cursor) respond({ data: ['worker', 'closed'], nextCursor: 'page2' });
                    else {
                        assert.equal(message.params.cursor, 'page2');
                        respond({ data: ['waiting-child'], nextCursor: null });
                    }
                    break;
                case 'thread/read':
                    assert.equal(message.params.includeTurns, false);
                    if (['worker', 'closed'].includes(message.params.threadId)) respond({ thread: { status: { type: 'active' } } });
                    else {
                        // An incoming request with a colliding ID must not consume the pending response.
                        send(socket, { id: message.id, method: 'item/commandExecution/requestApproval', params: {} });
                        // A live update must beat this stale snapshot even before initial loading finishes.
                        status('waiting-child', 'active', ['waitingOnUserInput']);
                        status('closed', 'notLoaded');
                        respond({ thread: { status: { type: 'idle' } } });
                    }
                    break;
            }
        }
    });
});

try {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const port = server.address().port;
    child = spawn(process.argv[2] ?? '.build/release/falcon-notifier', ['--watch', '--server', `ws://127.0.0.1:${port}`],
        { stdio: ['ignore', 'pipe', 'inherit'] });
    child.on('error', error => { throw error; });
    const levels = [];
    for await (const line of createInterface({ input: child.stdout })) {
        const { level, summary } = JSON.parse(line);
        console.log(`${level}: ${summary}`);
        if (level === 'unavailable' && levels.at(-1) === level) continue;
        levels.push(level);
        phase++;
        switch (levels.length) {
            case 1: assert.equal(level, 'attention'); status('waiting-child', 'idle'); break;
            case 2: assert.equal(level, 'busy'); status('worker', 'active', ['waitingOnApproval']); break;
            case 3: assert.equal(level, 'attention'); status('worker', 'active'); break;
            case 4: assert.equal(level, 'busy'); status('worker', 'notLoaded'); break;
            case 5: assert.equal(level, 'ready'); status('stale', 'active', ['waitingOnApproval']); break;
            // No completion notification: the next poll must clear this disappeared session.
            case 6: assert.equal(level, 'attention'); break;
            case 7: assert.equal(level, 'ready'); activeSocket.destroy(); break;
            case 8: assert.equal(level, 'unavailable'); break;
            case 9:
                assert.equal(level, 'ready');
                assert.ok(connectionCount >= 2);
                console.log('Passed: pagination, approvals, user input, snapshot races, read-only behavior, polling, unload, disconnect and reconnect.');
                cleanup();
                break;
        }
        if (levels.length === 9) break;
    }
    assert.deepEqual(levels, ['attention', 'busy', 'attention', 'busy', 'ready', 'attention', 'ready', 'unavailable', 'ready']);
} finally { cleanup(); }
