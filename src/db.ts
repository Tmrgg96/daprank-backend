import { Pool } from "pg";

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

export async function initDB() {
  const fs = await import("fs");
  const path = await import("path");
  const sqlPath = path.join(__dirname, "..", "init.sql");
  if (fs.existsSync(sqlPath)) {
    const sql = fs.readFileSync(sqlPath, "utf-8");
    await pool.query(sql);
    console.log("[DB] Schema initialized");
  }
}
