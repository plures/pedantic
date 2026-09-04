import { createLocalService } from "./local-service.js";

const profileId = readProfileId(process.argv.slice(2));
const authorizationToken = process.env.PEDANTIC_LOCAL_TOKEN;

if (!authorizationToken) {
  throw new Error("PEDANTIC_LOCAL_TOKEN is required to start the local Pedantic service.");
}

const service = createLocalService({
  profileId,
  authorizationToken,
  version: "0.1.0",
});

await service.start();
console.log(`pedantic-service listening on ${service.pipeName}`);

async function stop(): Promise<void> {
  await service.stop();
  process.exit(0);
}

process.once("SIGINT", stop);
process.once("SIGTERM", stop);

function readProfileId(args: string[]): string {
  const profileFlag = args.indexOf("--profile");
  if (profileFlag < 0) {
    return "default";
  }

  const profileId = args[profileFlag + 1];
  if (!profileId) {
    throw new Error("--profile requires a profile identifier.");
  }
  return profileId;
}
