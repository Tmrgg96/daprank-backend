import express from "express";
import cors from "cors";
import { pool, initDB } from "./db";
import { generateToken, authMiddleware, AuthRequest } from "./auth";

const app = express();
app.use(cors());
app.use(express.json({ limit: "10mb" }));

const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY || "";
const REVENUECAT_API_KEY = process.env.REVENUECAT_API_KEY || "";
const REVENUECAT_WEBHOOK_SECRET = process.env.REVENUECAT_WEBHOOK_SECRET || "";
const DAILY_CHECK_SECRET = process.env.DAILY_CHECK_SECRET || "";

// --------------- Health ---------------
app.get("/health", (_req, res) => res.json({ ok: true }));

// --------------- Anonymous Auth ---------------
app.post("/auth/anonymous", async (_req, res) => {
  try {
    const userResult = await pool.query(
      "INSERT INTO users DEFAULT VALUES RETURNING id"
    );
    const userId: string = userResult.rows[0].id;
    await pool.query(
      "INSERT INTO user_credits (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING",
      [userId]
    );
    const token = generateToken(userId);
    res.json({ access_token: token, user_id: userId });
  } catch (err) {
    console.error("[auth/anonymous]", err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- Templates (public) ---------------
app.get("/rest/v1/prank_templates", async (req, res) => {
  try {
    const { rows } = await pool.query(
      "SELECT id, title, image_name, prompt, is_active, sort_order, created_at, updated_at FROM prank_templates WHERE is_active = true ORDER BY sort_order ASC"
    );
    res.json(rows);
  } catch (err) {
    console.error("[templates]", err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- User Credits ---------------
app.get("/rest/v1/user_credits", authMiddleware, async (req: AuthRequest, res) => {
  try {
    const { rows } = await pool.query(
      "SELECT * FROM user_credits WHERE user_id = $1 LIMIT 1",
      [req.userId]
    );
    res.json(rows);
  } catch (err) {
    console.error("[user_credits GET]", err);
    res.status(500).json({ error: String(err) });
  }
});

app.post("/rest/v1/user_credits", authMiddleware, async (req: AuthRequest, res) => {
  try {
    const { rows } = await pool.query(
      `INSERT INTO user_credits (user_id) VALUES ($1)
       ON CONFLICT (user_id) DO NOTHING
       RETURNING *`,
      [req.userId]
    );
    if (rows.length === 0) {
      const existing = await pool.query(
        "SELECT * FROM user_credits WHERE user_id = $1",
        [req.userId]
      );
      res.json(existing.rows);
    } else {
      res.json(rows);
    }
  } catch (err) {
    console.error("[user_credits POST]", err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- RPC: can_generate ---------------
app.post("/rest/v1/rpc/can_generate", authMiddleware, async (req: AuthRequest, res) => {
  try {
    const { rows } = await pool.query("SELECT can_generate($1) AS result", [
      req.userId,
    ]);
    res.json(rows[0].result);
  } catch (err) {
    console.error("[can_generate]", err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- OpenRouter Proxy ---------------
app.post("/functions/v1/openrouter-proxy", authMiddleware, async (req: AuthRequest, res) => {
  const startedAt = Date.now();
  try {
    if (!OPENROUTER_API_KEY) {
      res.status(500).json({ error: "Missing OPENROUTER_API_KEY" });
      return;
    }

    const skipConsume =
      (req.headers["x-no-consume"] || "").toString().toLowerCase() === "true";
    let watermark = false;

    if (skipConsume) {
      const { rows } = await pool.query("SELECT can_generate($1) AS result", [
        req.userId,
      ]);
      watermark = !!rows[0]?.result?.watermark;
    } else {
      const { rows } = await pool.query(
        "SELECT consume_generation($1) AS result",
        [req.userId]
      );
      const consume = rows[0]?.result;
      if (!consume?.allowed) {
        res.status(402).json({ error: "no_credits", details: consume });
        return;
      }
      watermark = !!consume?.watermark;
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 90_000);

    const upstream = await fetch(
      "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${OPENROUTER_API_KEY}`,
          "HTTP-Referer": process.env.HTTP_REFERER || "https://daprank.com",
          "X-Title": process.env.X_TITLE || "DaPrank AI Photo Editor",
        },
        body: JSON.stringify(req.body),
        signal: controller.signal,
      }
    ).finally(() => clearTimeout(timeout));

    const text = await upstream.text();
    console.log(
      `[openrouter-proxy] status=${upstream.status} latency=${Date.now() - startedAt}ms`
    );

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (watermark) headers["X-Watermark"] = "true";

    res.status(upstream.status).set(headers).send(text);
  } catch (err) {
    console.error(`[openrouter-proxy] error after ${Date.now() - startedAt}ms`, err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- Sync Subscription ---------------
app.post("/functions/v1/sync-subscription", authMiddleware, async (req: AuthRequest, res) => {
  try {
    if (!REVENUECAT_API_KEY) {
      res.status(500).json({ error: "Missing REVENUECAT_API_KEY" });
      return;
    }

    const userId = req.userId!;
    const rcResponse = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${userId}`,
      {
        headers: {
          Authorization: `Bearer ${REVENUECAT_API_KEY}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      }
    );

    if (!rcResponse.ok) {
      if (rcResponse.status === 404) {
        await pool.query(
          "SELECT apply_subscription_change($1, $2, $3, $4)",
          [userId, "inactive", null, null]
        );
        res.json({ status: "inactive", message: "User not found in RC" });
        return;
      }
      const text = await rcResponse.text();
      throw new Error(`RevenueCat API Error: ${rcResponse.status} ${text}`);
    }

    const rcData = await rcResponse.json();
    const entitlements = rcData.subscriber?.entitlements || {};

    let isActive = false;
    let expiresAt: string | null = null;
    let productId = "";

    for (const ent of Object.values(entitlements) as any[]) {
      const expiresDate = ent.expires_date ? new Date(ent.expires_date) : null;
      if (expiresDate === null || expiresDate > new Date()) {
        isActive = true;
        expiresAt = ent.expires_date;
        productId = ent.product_identifier;
        break;
      }
    }

    const status = isActive ? "active" : "inactive";
    let subType: string | null = null;
    if (isActive && productId) {
      const pId = productId.toLowerCase();
      subType =
        pId.includes("year") || pId.includes("annual") || pId.includes("12mo")
          ? "yearly"
          : "monthly";
    }

    console.log(
      `[sync-subscription] user=${userId} status=${status} type=${subType}`
    );

    await pool.query("SELECT apply_subscription_change($1, $2, $3, $4)", [
      userId,
      status,
      subType,
      expiresAt,
    ]);

    res.json({ ok: true, status, type: subType });
  } catch (err) {
    console.error("[sync-subscription]", err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- RevenueCat Webhook ---------------
app.post("/functions/v1/revenuecat-webhook", async (req, res) => {
  try {
    if (REVENUECAT_WEBHOOK_SECRET) {
      const authHeader = req.headers.authorization || "";
      const xSecret =
        (req.headers["x-webhook-secret"] as string) || "";
      const bearer = authHeader.startsWith("Bearer ")
        ? authHeader.slice(7)
        : "";
      if (
        bearer !== REVENUECAT_WEBHOOK_SECRET &&
        xSecret !== REVENUECAT_WEBHOOK_SECRET
      ) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }
    }

    const payload = req.body;
    const event = payload.event ?? payload;

    const appUserId = event.app_user_id;
    if (!appUserId) {
      res.status(400).json({ error: "Missing app_user_id" });
      return;
    }

    const type = (event.type || "").toUpperCase();
    if (type === "TEST") {
      res.json({ ok: true, note: "TEST event ignored" });
      return;
    }

    const expiresAt = event.expiration_at_ms
      ? new Date(event.expiration_at_ms)
      : null;

    let status: "active" | "inactive" = "active";
    if (type === "EXPIRATION") {
      status = "inactive";
    } else if (expiresAt && expiresAt.getTime() <= Date.now()) {
      status = "inactive";
    }

    let subType: string | null = null;
    if (status === "active") {
      const productId = (event.product_id || "").toLowerCase();
      subType =
        productId.includes("year") ||
        productId.includes("annual") ||
        productId.includes("12mo")
          ? "yearly"
          : "monthly";
    }

    console.log(
      `[revenuecat-webhook] type=${type} user=${appUserId} status=${status} subType=${subType}`
    );

    // Ensure user exists before applying subscription change
    await pool.query(
      "INSERT INTO users (id) VALUES ($1) ON CONFLICT (id) DO NOTHING",
      [appUserId]
    );

    await pool.query("SELECT apply_subscription_change($1, $2, $3, $4)", [
      appUserId,
      status,
      subType,
      expiresAt ? expiresAt.toISOString() : null,
    ]);

    res.json({ ok: true });
  } catch (err) {
    console.error("[revenuecat-webhook]", err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- Daily Check (cron) ---------------
app.post("/functions/v1/credits-daily-check", async (req, res) => {
  try {
    if (DAILY_CHECK_SECRET) {
      const auth = req.headers.authorization || "";
      if (auth !== `Bearer ${DAILY_CHECK_SECRET}`) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }
    }
    await pool.query("SELECT reset_expired_and_refresh_active()");
    res.json({ ok: true });
  } catch (err) {
    console.error("[daily-check]", err);
    res.status(500).json({ error: String(err) });
  }
});

// --------------- Start ---------------
const PORT = parseInt(process.env.PORT || "3000", 10);

async function main() {
  await initDB();
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`[DaPrank API] listening on :${PORT}`);
  });
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
