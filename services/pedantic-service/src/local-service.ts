import { timingSafeEqual } from "node:crypto";
import { createServer, type Server, type Socket } from "node:net";
import { MAX_FRAME_BYTES, type LocalServiceRequest, type LocalServiceResponse, isResponse, parseRequest } from "./protocol.js";

export interface LocalServiceConfig {
  profileId: string;
  authorizationToken: string;
  version: string;
}

export interface LocalService {
  pipeName: string;
  start(): Promise<void>;
  stop(): Promise<void>;
}

export function createLocalService(config: LocalServiceConfig): LocalService {
  assertProfileId(config.profileId);
  assertToken(config.authorizationToken);

  const pipeName = pipeNameForProfile(config.profileId);
  const server = createServer((socket) => attachConnection(socket, config));

  return {
    pipeName,
    async start(): Promise<void> {
      await new Promise<void>((resolve, reject) => {
        server.once("error", reject);
        server.listen(pipeName, () => {
          server.off("error", reject);
          resolve();
        });
      });
    },
    async stop(): Promise<void> {
      await closeServer(server);
    },
  };
}

export function pipeNameForProfile(profileId: string): string {
  assertProfileId(profileId);
  return `\\\\.\\pipe\\pedantic-${profileId}`;
}

function attachConnection(socket: Socket, config: LocalServiceConfig): void {
  socket.setEncoding("utf8");
  let pending = "";

  socket.on("data", (chunk: string) => {
    pending += chunk;
    if (Buffer.byteLength(pending, "utf8") > MAX_FRAME_BYTES) {
      socket.destroy(new Error("Local service request exceeded the frame limit."));
      return;
    }

    let newlineIndex = pending.indexOf("\n");
    while (newlineIndex >= 0) {
      const frame = pending.slice(0, newlineIndex).trim();
      pending = pending.slice(newlineIndex + 1);
      if (frame.length > 0) {
        writeResponse(socket, handleRequest(frame, config));
      }
      newlineIndex = pending.indexOf("\n");
    }
  });
}

function handleRequest(frame: string, config: LocalServiceConfig): LocalServiceResponse {
  const parsed = parseRequest(frame);
  if (isResponse(parsed)) {
    return parsed;
  }

  if (!hasExpectedAuthorization(parsed.authorization, config.authorizationToken)) {
    return {
      id: parsed.id,
      ok: false,
      error: { code: "unauthorized", message: "Local service authorization failed." },
    };
  }

  if (parsed.profileId !== config.profileId) {
    return {
      id: parsed.id,
      ok: false,
      error: { code: "unauthorized", message: "Request profile does not match this service instance." },
    };
  }

  return healthResponse(parsed, config);
}

function healthResponse(request: LocalServiceRequest, config: LocalServiceConfig): LocalServiceResponse {
  if (request.method !== "service.health") {
    return {
      id: request.id,
      ok: false,
      error: { code: "method_not_found", message: `Method '${request.method}' is not registered.` },
    };
  }

  return {
    id: request.id,
    ok: true,
    result: {
      profileId: config.profileId,
      service: "pedantic-service",
      version: config.version,
    },
  };
}

function hasExpectedAuthorization(provided: string, expected: string): boolean {
  const providedBytes = Buffer.from(provided, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  return providedBytes.length === expectedBytes.length && timingSafeEqual(providedBytes, expectedBytes);
}

function assertProfileId(profileId: string): void {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(profileId)) {
    throw new Error("Profile identifiers must be 1-64 characters of letters, numbers, underscores, or hyphens.");
  }
}

function assertToken(token: string): void {
  if (Buffer.byteLength(token, "utf8") < 32) {
    throw new Error("PEDANTIC_LOCAL_TOKEN must contain at least 32 bytes.");
  }
}

function writeResponse(socket: Socket, response: LocalServiceResponse): void {
  socket.write(`${JSON.stringify(response)}\n`);
}

async function closeServer(server: Server): Promise<void> {
  if (!server.listening) {
    return;
  }

  await new Promise<void>((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}
