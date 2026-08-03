import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const binary = process.env.PEDANTIC_MCP_BINARY
  ?? resolve('rust', 'target', 'debug', process.platform === 'win32' ? 'pedantic-mcp.exe' : 'pedantic-mcp');

if (!existsSync(binary)) {
  throw new Error(`Pedantic MCP binary not found: ${binary}. Run cargo build -p pedantic-mcp first.`);
}

const server = spawn(binary, [], {
  stdio: ['pipe', 'pipe', 'pipe'],
  env: process.env,
});

let stderr = '';
server.stderr.setEncoding('utf8');
server.stderr.on('data', (chunk) => { stderr += chunk; });

const lines = createInterface({ input: server.stdout });
const pending = new Map();
let nextId = 1;

lines.on('line', (line) => {
  const message = JSON.parse(line);
  if (Object.hasOwn(message, 'id') && pending.has(message.id)) {
    pending.get(message.id).resolve(message);
    pending.delete(message.id);
  }
});

server.once('error', (error) => {
  for (const { reject } of pending.values()) reject(error);
  pending.clear();
});

function request(method, params) {
  const id = nextId++;
  const reply = new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    setTimeout(() => {
      if (pending.delete(id)) reject(new Error(`Timed out waiting for ${method}; stderr: ${stderr}`));
    }, 20_000).unref();
  });
  server.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
  return reply;
}

function notify(method, params) {
  server.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);
}

try {
  const initialized = await request('initialize', {
    protocolVersion: '2025-03-26',
    capabilities: {},
    clientInfo: { name: 'pedantic-mcp-smoke', version: '1.0.0' },
  });
  if (initialized.error) throw new Error(`MCP initialize failed: ${JSON.stringify(initialized.error)}`);
  notify('notifications/initialized', {});

  const tools = await request('tools/list', {});
  if (tools.error) throw new Error(`MCP tools/list failed: ${JSON.stringify(tools.error)}`);
  const names = new Set(tools.result.tools.map((tool) => tool.name));
  for (const expected of ['resource_list', 'resource_get', 'resource_test', 'resource_export', 'config_export', 'config_validate']) {
    if (!names.has(expected)) throw new Error(`MCP tool is missing: ${expected}`);
  }

  const listed = await request('tools/call', {
    name: 'resource_list',
    arguments: { filter: 'SimpleDSC*' },
  });
  if (listed.error || listed.result.isError) throw new Error(`MCP resource_list failed: ${JSON.stringify(listed.error ?? listed.result)}`);
  const listText = listed.result.content.map((item) => item.text ?? '').join('\n');
  if (!listText.includes('SimpleDSC/PackageInstaller')) {
    throw new Error(`MCP resource_list did not discover SimpleDSC/PackageInstaller: ${listText}`);
  }

  const current = await request('tools/call', {
    name: 'resource_get',
    arguments: {
      resource_type: 'SimpleDSC/PackageInstaller',
      instance: { name: 'mcp-smoke', packages: ['Git.Git'], method: 'winget', ensure: 'Present' },
    },
  });
  if (current.error || current.result.isError) throw new Error(`MCP resource_get failed: ${JSON.stringify(current.error ?? current.result)}`);
  const getText = current.result.content.map((item) => item.text ?? '').join('\n');
  if (!getText.includes('actualState')) {
    throw new Error(`MCP resource_get returned no DSC actual state: ${getText}`);
  }

  console.log('MCP_SMOKE_OK tools=resource_list,resource_get');
} finally {
  server.stdin.end();
  server.kill();
}
