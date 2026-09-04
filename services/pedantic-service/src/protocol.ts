export const MAX_FRAME_BYTES = 64 * 1024;

export interface LocalServiceRequest {
  id: string;
  method: "service.health" | string;
  profileId: string;
  authorization: string;
}

export interface LocalServiceResponse {
  id: string | null;
  ok: boolean;
  result?: Record<string, unknown>;
  error?: {
    code: "invalid_request" | "unauthorized" | "method_not_found";
    message: string;
  };
}

export function parseRequest(frame: string): LocalServiceRequest | LocalServiceResponse {
  let candidate: unknown;
  try {
    candidate = JSON.parse(frame);
  } catch {
    return invalidRequest(null, "Request must be valid JSON.");
  }

  if (!isRecord(candidate)) {
    return invalidRequest(null, "Request must be a JSON object.");
  }

  const id = typeof candidate.id === "string" ? candidate.id : null;
  if (
    typeof candidate.id !== "string" ||
    typeof candidate.method !== "string" ||
    typeof candidate.profileId !== "string" ||
    typeof candidate.authorization !== "string"
  ) {
    return invalidRequest(id, "Request requires string id, method, profileId, and authorization fields.");
  }

  return {
    id: candidate.id,
    method: candidate.method,
    profileId: candidate.profileId,
    authorization: candidate.authorization,
  };
}

export function invalidRequest(id: string | null, message: string): LocalServiceResponse {
  return {
    id,
    ok: false,
    error: { code: "invalid_request", message },
  };
}

export function isResponse(value: LocalServiceRequest | LocalServiceResponse): value is LocalServiceResponse {
  return "ok" in value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
