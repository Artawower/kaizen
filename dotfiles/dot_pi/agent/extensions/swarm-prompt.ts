import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "swarm_prompt",
    label: "Swarm Prompt",

    description:
      "Send a prompt to an existing managed Herdr agent, wait until it settles, " +
      "and return the final agent output in one tool call.",

    parameters: Type.Object({
      target: Type.String({
        description: "Existing managed Herdr agent name",
      }),

      text: Type.String({
        description: "Prompt to send to the agent",
      }),

      timeoutMs: Type.Optional(
        Type.Number({
          description: "Maximum wait time in milliseconds",
        }),
      ),
    }),

    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const timeoutMs = params.timeoutMs ?? 1_800_000;

      const prompt = await pi.exec(
        "herdr",
        [
          "agent",
          "prompt",
          params.target,
          params.text,
          "--wait",
          "--timeout",
          String(timeoutMs),
        ],
        {
          cwd: ctx.cwd,
          signal,
        },
      );

      if (prompt.code !== 0) {
        return {
          content: [
            {
              type: "text",
              text:
                `Herdr prompt failed (exit ${prompt.code}).\n` +
                `${prompt.stderr || prompt.stdout}`,
            },
          ],
          details: {
            target: params.target,
            exitCode: prompt.code,
          },
        };
      }

      // `prompt --wait` waits for completion, but for orchestration audit we
      // want the final textual result from the persistent agent.
      const read = await pi.exec(
        "herdr",
        [
          "agent",
          "read",
          params.target,
          "--source",
          "recent-unwrapped",
          "--lines",
          "120",
        ],
        {
          cwd: ctx.cwd,
          signal,
        },
      );

      if (read.code !== 0) {
        return {
          content: [
            {
              type: "text",
              text:
                `Agent completed, but reading the result failed.\n` +
                `${read.stderr || read.stdout}`,
            },
          ],
          details: {
            target: params.target,
            exitCode: read.code,
          },
        };
      }

      return {
        content: [
          {
            type: "text",
            text: read.stdout.trim(),
          },
        ],
        details: {
          target: params.target,
          timeoutMs,
        },
      };
    },
  });
}
