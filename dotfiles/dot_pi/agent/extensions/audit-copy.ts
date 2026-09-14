// @ts-nocheck

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";

const MAX_USER_TEXT = 8_000;
const MAX_ASSISTANT_TEXT = 4_000;
const MAX_TOOL_ARGS = 800;
const MAX_HERDR_RESULT = 1_500;
const MAX_ERROR = 2_000;

function clip(value: unknown, limit: number): string {
  const text =
    typeof value === "string" ? value : JSON.stringify(value ?? null);

  if (text.length <= limit) return text;

  const half = Math.floor(limit / 2);

  return text.slice(0, half) + "\n…TRUNCATED…\n" + text.slice(-half);
}

function extractText(content: unknown): string {
  if (typeof content === "string") return content;

  if (!Array.isArray(content)) return "";

  return content
    .filter((item) => item && typeof item === "object" && item.type === "text")
    .map((item) => item.text ?? "")
    .filter(Boolean)
    .join("\n");
}

function compactUsage(usage: any) {
  if (!usage) return undefined;

  return {
    input: usage.input,
    output: usage.output,
    cacheRead: usage.cacheRead,
    cacheWrite: usage.cacheWrite,
    cost: usage.cost?.total,
  };
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("audit-copy", {
    description: "Copy compact orchestration trace to clipboard",

    handler: async (_args, ctx) => {
      const branch = ctx.sessionManager.getBranch();
      const events: any[] = [];

      events.push({
        event: "session",
        cwd: ctx.cwd,
        sessionFile: ctx.sessionManager.getSessionFile(),
      });

      for (const entry of branch) {
        const timestamp = entry.timestamp;

        if (entry.type === "model_change") {
          events.push({
            event: "model",
            timestamp,
            provider: entry.provider,
            model: entry.modelId,
          });
          continue;
        }

        if (entry.type === "thinking_level_change") {
          events.push({
            event: "thinking_level",
            timestamp,
            level: entry.thinkingLevel,
          });
          continue;
        }

        if (entry.type !== "message") continue;

        const message = entry.message;
        if (!message) continue;

        if (message.role === "user") {
          const text = extractText(message.content);

          if (text.trim()) {
            events.push({
              event: "user",
              timestamp,
              text: clip(text, MAX_USER_TEXT),
            });
          }

          continue;
        }

        if (message.role === "assistant") {
          const assistantText: string[] = [];

          if (Array.isArray(message.content)) {
            for (const item of message.content) {
              if (!item || typeof item !== "object") continue;

              // Intentionally discard reasoning/thinking and signatures.
              if (item.type === "text") {
                if (item.text?.trim()) {
                  assistantText.push(item.text);
                }

                continue;
              }

              if (item.type === "toolCall") {
                events.push({
                  event: "tool_call",
                  timestamp,
                  id: item.id,
                  tool: item.name,
                  args: clip(item.arguments, MAX_TOOL_ARGS),
                });
              }
            }
          }

          if (assistantText.length > 0) {
            events.push({
              event: "assistant",
              timestamp,
              text: clip(assistantText.join("\n"), MAX_ASSISTANT_TEXT),
              usage: compactUsage(message.usage),
              stopReason: message.stopReason,
            });
          } else if (message.usage) {
            events.push({
              event: "usage",
              timestamp,
              usage: compactUsage(message.usage),
              stopReason: message.stopReason,
            });
          }

          if (message.errorMessage) {
            events.push({
              event: "model_error",
              timestamp,
              text: clip(message.errorMessage, MAX_ERROR),
            });
          }

          continue;
        }

        if (message.role === "toolResult") {
          const tool = String(message.toolName ?? "");
          const isError = Boolean(message.isError);

          // Successful ordinary tool output is the main source of huge
          // sessions and usually irrelevant for orchestration analysis.
          //
          // Keep:
          //   - every herdr_* result
          //   - every failed tool result
          //
          // Tool CALLS themselves are preserved above for every tool.
          if (!isError && !tool.startsWith("herdr_")) {
            continue;
          }

          events.push({
            event: "tool_result",
            timestamp,
            id: message.toolCallId,
            tool,
            error: isError,
            text: clip(
              extractText(message.content),
              isError ? MAX_ERROR : MAX_HERDR_RESULT,
            ),
          });
        }
      }

      const output = events.map((event) => JSON.stringify(event)).join("\n");

      try {
        execFileSync("pbcopy", [], {
          input: output,
          encoding: "utf8",
        });
      } catch (error) {
        ctx.ui.notify(`audit-copy: pbcopy failed: ${String(error)}`, "error");
        return;
      }

      const bytes = Buffer.byteLength(output);
      const size =
        bytes >= 1024 * 1024
          ? `${(bytes / 1024 / 1024).toFixed(2)} MB`
          : `${Math.round(bytes / 1024)} KB`;

      ctx.ui.notify(`Copied ${events.length} audit events (${size})`, "info");
    },
  });
}
