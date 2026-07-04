import type { ExtendKcContext } from "keycloakify/login";

export type KcContext = ExtendKcContext<{
    properties: Record<string, string | undefined>;
  },
  Record<string, Record<string, unknown>>
>;
