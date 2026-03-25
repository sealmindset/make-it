import { test, expect } from "@playwright/test";

test("frontend loads", async ({ page }) => {
  const resp = await page.goto("/");
  expect(resp?.status()).toBeLessThan(400);
});

test("backend health endpoint", async ({ request }) => {
  const resp = await request.get("/api/health");
  expect(resp.status()).toBe(200);
  expect(await resp.json()).toEqual({ status: "ok" });
});
