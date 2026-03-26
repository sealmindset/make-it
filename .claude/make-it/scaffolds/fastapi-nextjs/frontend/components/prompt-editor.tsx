"use client";

import { useState } from "react";
import { Eye, EyeOff, HelpCircle } from "lucide-react";
import { SafetyIndicator } from "@/components/safety-indicator";
import { VariablePill, extractVariables } from "@/components/variable-pill";

interface PromptEditorProps {
  content: string;
  systemMessage: string;
  parameters: Record<string, unknown> | null;
  onChange: (field: "content" | "system_message" | "parameters", value: unknown) => void;
  readOnly?: boolean;
}

const variableDescriptions: Record<string, string> = {
  user_input: "What the user types or asks",
  context: "Background information provided to the AI",
  history: "Previous conversation messages",
  document: "The document or text being analyzed",
  query: "The search or analysis query",
  format: "The desired output format",
  language: "The target language for responses",
  // [VARIABLE_DESCRIPTIONS] -- app-specific variable descriptions added here
};

export function PromptEditor({
  content,
  systemMessage,
  parameters,
  onChange,
  readOnly = false,
}: PromptEditorProps) {
  const [guidedMode, setGuidedMode] = useState(true);
  const [showAdvanced, setShowAdvanced] = useState(false);

  const variables = extractVariables(content);
  const temperature = (parameters?.temperature as number) ?? 0.7;
  const maxTokens = (parameters?.max_tokens as number) ?? 2048;

  const handleParameterChange = (key: string, value: unknown) => {
    onChange("parameters", { ...(parameters || {}), [key]: value });
  };

  return (
    <div className="space-y-6">
      {/* Mode toggle */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium">Editing Mode</span>
        </div>
        <button
          onClick={() => setGuidedMode(!guidedMode)}
          className="inline-flex items-center gap-2 rounded-md px-3 py-1.5 text-xs font-medium transition-colors"
          style={{
            backgroundColor:
              "color-mix(in oklch, var(--foreground) 8%, transparent)",
            color: "var(--muted-foreground)",
          }}
        >
          {guidedMode ? (
            <>
              <Eye className="h-3.5 w-3.5" />
              Guided Mode
            </>
          ) : (
            <>
              <EyeOff className="h-3.5 w-3.5" />
              Advanced Mode
            </>
          )}
        </button>
      </div>

      {/* Main instructions (content) -- SAFE zone */}
      <div
        className="rounded-lg p-4"
        style={{
          borderLeft: "3px solid var(--success)",
          backgroundColor:
            "color-mix(in oklch, var(--success) 3%, var(--card))",
        }}
      >
        <div className="mb-2 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold">Instructions</label>
            <SafetyIndicator level="safe" />
          </div>
        </div>

        {guidedMode && (
          <p
            className="mb-3 text-xs"
            style={{ color: "var(--muted-foreground)" }}
          >
            Write what you want the AI to do. Be specific about the task,
            format, and any rules it should follow. This is the main text the AI
            reads before responding.
          </p>
        )}

        <textarea
          value={content}
          onChange={(e) => onChange("content", e.target.value)}
          readOnly={readOnly}
          rows={10}
          className="w-full resize-y rounded-md border px-3 py-2 text-sm font-mono"
          style={{
            borderColor: "var(--input)",
            backgroundColor: "var(--background)",
            color: "var(--foreground)",
          }}
          placeholder="Tell the AI what to do..."
        />

        {/* Variable pills */}
        {variables.length > 0 && (
          <div className="mt-3">
            <div className="flex items-center gap-1.5 mb-2">
              <span
                className="text-xs font-medium"
                style={{ color: "var(--muted-foreground)" }}
              >
                Dynamic values in this instruction:
              </span>
              {guidedMode && (
                <HelpCircle
                  className="h-3 w-3"
                  style={{ color: "var(--muted-foreground)" }}
                  title="These are placeholders that get replaced with real data when the AI runs"
                />
              )}
            </div>
            <div className="flex flex-wrap gap-2">
              {variables.map((v) => (
                <VariablePill
                  key={v}
                  name={v}
                  description={variableDescriptions[v]}
                />
              ))}
            </div>
          </div>
        )}
      </div>

      {/* AI Behavior (system_message) -- CAUTION zone */}
      <div
        className="rounded-lg p-4"
        style={{
          borderLeft: "3px solid var(--warning)",
          backgroundColor:
            "color-mix(in oklch, var(--warning) 3%, var(--card))",
        }}
      >
        <div className="mb-2 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold">AI Behavior</label>
            <SafetyIndicator level="caution" />
          </div>
        </div>

        {guidedMode && (
          <p
            className="mb-3 text-xs"
            style={{ color: "var(--muted-foreground)" }}
          >
            This defines the AI&apos;s personality and boundaries. Changes here
            affect how the AI interprets all instructions. Edit with care --
            small changes can significantly alter responses.
          </p>
        )}

        <textarea
          value={systemMessage}
          onChange={(e) => onChange("system_message", e.target.value)}
          readOnly={readOnly}
          rows={5}
          className="w-full resize-y rounded-md border px-3 py-2 text-sm font-mono"
          style={{
            borderColor: "var(--input)",
            backgroundColor: "var(--background)",
            color: "var(--foreground)",
          }}
          placeholder="Define the AI's role and constraints..."
        />
      </div>

      {/* Settings (parameters) -- CAUTION zone */}
      <div
        className="rounded-lg p-4"
        style={{
          borderLeft: "3px solid var(--warning)",
          backgroundColor:
            "color-mix(in oklch, var(--warning) 3%, var(--card))",
        }}
      >
        <div className="mb-2 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold">Settings</label>
            <SafetyIndicator level="caution" />
          </div>
        </div>

        {guidedMode ? (
          <div className="space-y-4">
            {/* Creativity slider (temperature) */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <label
                  className="text-xs font-medium"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  Creativity
                </label>
                <span className="text-xs" style={{ color: "var(--muted-foreground)" }}>
                  {temperature < 0.3
                    ? "Precise"
                    : temperature < 0.7
                      ? "Balanced"
                      : "Creative"}
                </span>
              </div>
              <input
                type="range"
                min={0}
                max={1}
                step={0.1}
                value={temperature}
                onChange={(e) =>
                  handleParameterChange("temperature", parseFloat(e.target.value))
                }
                disabled={readOnly}
                className="w-full accent-[var(--primary)]"
              />
              <div
                className="flex justify-between text-xs mt-0.5"
                style={{ color: "var(--muted-foreground)" }}
              >
                <span>Precise</span>
                <span>Creative</span>
              </div>
            </div>

            {/* Max response length */}
            <div>
              <label
                className="text-xs font-medium mb-1 block"
                style={{ color: "var(--muted-foreground)" }}
              >
                Maximum response length (tokens)
              </label>
              <input
                type="number"
                min={1}
                max={128000}
                value={maxTokens}
                onChange={(e) =>
                  handleParameterChange(
                    "max_tokens",
                    parseInt(e.target.value) || 2048
                  )
                }
                disabled={readOnly}
                className="w-32 rounded-md border px-3 py-1.5 text-sm"
                style={{
                  borderColor: "var(--input)",
                  backgroundColor: "var(--background)",
                  color: "var(--foreground)",
                }}
              />
              {guidedMode && (
                <p
                  className="mt-1 text-xs"
                  style={{ color: "var(--muted-foreground)" }}
                >
                  Higher values allow longer responses. 1 token is roughly 4
                  characters.
                </p>
              )}
            </div>

            {/* Advanced toggle */}
            <button
              onClick={() => setShowAdvanced(!showAdvanced)}
              className="text-xs font-medium"
              style={{ color: "var(--primary)" }}
            >
              {showAdvanced ? "Hide" : "Show"} advanced settings (JSON)
            </button>

            {showAdvanced && (
              <textarea
                value={JSON.stringify(parameters || {}, null, 2)}
                onChange={(e) => {
                  try {
                    onChange("parameters", JSON.parse(e.target.value));
                  } catch {
                    // Invalid JSON -- don't update
                  }
                }}
                readOnly={readOnly}
                rows={6}
                className="w-full resize-y rounded-md border px-3 py-2 text-xs font-mono"
                style={{
                  borderColor: "var(--input)",
                  backgroundColor: "var(--background)",
                  color: "var(--foreground)",
                }}
              />
            )}
          </div>
        ) : (
          /* Advanced mode: raw JSON */
          <textarea
            value={JSON.stringify(parameters || {}, null, 2)}
            onChange={(e) => {
              try {
                onChange("parameters", JSON.parse(e.target.value));
              } catch {
                // Invalid JSON -- don't update
              }
            }}
            readOnly={readOnly}
            rows={8}
            className="w-full resize-y rounded-md border px-3 py-2 text-sm font-mono"
            style={{
              borderColor: "var(--input)",
              backgroundColor: "var(--background)",
              color: "var(--foreground)",
            }}
          />
        )}
      </div>
    </div>
  );
}
