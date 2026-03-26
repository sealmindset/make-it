/**
 * Capture screenshots from a running /make-it app for the User Guide.
 * Run: node capture.mjs (from this directory, with ratify app running)
 */
import { chromium } from "playwright";
import { fileURLToPath } from "url";
import path from "path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FRONTEND = "http://localhost:3100";
const MOCK_OIDC = "http://localhost:10090";

async function main() {
  const browser = await chromium.launch({ headless: true });

  // --- Screenshot 1: Mock-OIDC user picker (try-it-login.png) ---
  console.log("1/3 Capturing login screen...");
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await ctx.newPage();
    const authUrl = `${MOCK_OIDC}/authorize?client_id=mock-oidc-client&redirect_uri=${encodeURIComponent(FRONTEND + "/api/auth/callback")}&response_type=code&scope=openid%20profile%20email&state=screenshot`;
    await page.goto(authUrl);
    await page.waitForTimeout(2000);
    await page.screenshot({ path: path.join(__dirname, "try-it-login.png") });
    console.log("   ✓ try-it-login.png");
    await ctx.close();
  }

  // --- Screenshot 2: Dashboard as admin (app-dashboard.png) ---
  console.log("2/3 Capturing dashboard...");
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await ctx.newPage();

    // Hit the login endpoint with login_hint to auto-login as admin
    await page.goto(`${FRONTEND}/api/auth/login?login_hint=mock-admin`);
    await page.waitForTimeout(3000);

    // If we landed on mock-oidc picker, click the admin user
    if (page.url().includes(MOCK_OIDC) || page.url().includes("10090")) {
      const btn = page.locator("[data-subject='mock-admin']").or(page.locator("text=Admin User")).or(page.locator("text=mock-admin"));
      if (await btn.count() > 0) {
        await btn.first().click();
        await page.waitForTimeout(3000);
      }
    }

    // Make sure we're on the dashboard
    if (!page.url().includes("/dashboard")) {
      await page.goto(`${FRONTEND}/dashboard`);
      await page.waitForTimeout(2000);
    }

    await page.waitForTimeout(1000);
    await page.screenshot({ path: path.join(__dirname, "app-dashboard.png") });
    console.log("   ✓ app-dashboard.png");
    await ctx.close();
  }

  // --- Screenshot 3: Admin page showing roles/users (admin-panel.png - bonus) ---
  console.log("3/3 Capturing admin panel...");
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await ctx.newPage();

    // Login as admin
    await page.goto(`${FRONTEND}/api/auth/login?login_hint=mock-admin`);
    await page.waitForTimeout(3000);

    if (page.url().includes(MOCK_OIDC) || page.url().includes("10090")) {
      const btn = page.locator("[data-subject='mock-admin']").or(page.locator("text=Admin User")).or(page.locator("text=mock-admin"));
      if (await btn.count() > 0) {
        await btn.first().click();
        await page.waitForTimeout(3000);
      }
    }

    // Navigate to admin users page
    await page.goto(`${FRONTEND}/admin/users`);
    await page.waitForTimeout(2000);
    await page.screenshot({ path: path.join(__dirname, "admin-panel.png") });
    console.log("   ✓ admin-panel.png");
    await ctx.close();
  }

  await browser.close();
  console.log("\nDone! Screenshots saved to docs/screenshots/");
}

main().catch((err) => {
  console.error("Failed:", err.message);
  process.exit(1);
});
