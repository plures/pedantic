import { randomUUID } from "node:crypto";
import { connect } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import { createLocalService, type LocalService } from "../local-service.js";
import type { LocalServiceResponse } from "../protocol.js";

const token = "0123456789abcdef0123456789abcdef";
let service: LocalService | undefined;

afterEach(async () => {
  await service?.stop();
  service = undefined;
});

describe("local Pedantic service", () => {
  it("serves authenticated health requests over a profile-scoped named pipe", async () => {
    const profileId = `test-${randomUUID().replaceAll("-", "")}`;
    service = createLocalService({ profileId, authorizationToken: token, version: "test" });
    await service.start();

    await expect(send(service.pipeName, {
      id: "health-1",
      method: "service.health",
      profileId,
      authorization: token,
    })).resolves.toEqual({
      id: "health-1",
      ok: true,
      result: { profileId, service: "pedantic-service", version: "test" },
    });
  });

  it("rejects requests with an incorrect authorization token", async () => {
    const profileId = `test-${randomUUID().replaceAll("-", "")}`;
    service = createLocalService({ profileId, authorizationToken: token, version: "test" });
    await service.start();

    await expect(send(service.pipeName, {
      id: "health-2",
      method: "service.health",
      profileId,
      authorization: "incorrect-token-0123456789abcdef",
    })).resolves.toMatchObject({
      id: "health-2",
      ok: false,
      error: { code: "unauthorized" },
    });
  });

  it("does not expose unregistered operational methods", async () => {
    const profileId = `test-${randomUUID().replaceAll("-", "")}`;
    service = createLocalService({ profileId, authorizationToken: token, version: "test" });
    await service.start();

    await expect(send(service.pipeName, {
      id: "set-1",
      method: "effect.execute",
      profileId,
      authorization: token,
    })).resolves.toMatchObject({
      id: "set-1",
      ok: false,
      error: { code: "method_not_found" },
    });
  });
});

function send(pipeName: string, request: Record<string, string>): Promise<LocalServiceResponse> {
  return new Promise((resolve, reject) => {
    const socket = connect(pipeName);
    let buffer = "";

    socket.once("error", reject);
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => {
      buffer += chunk;
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex < 0) {
        return;
      }

      socket.end();
      resolve(JSON.parse(buffer.slice(0, newlineIndex)) as LocalServiceResponse);
    });
    socket.on("connect", () => {
      socket.write(`${JSON.stringify(request)}\n`);
    });
  });
}
