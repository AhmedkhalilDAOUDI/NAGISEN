import { h, render, Fragment } from "preact";
import { useState, useEffect, useMemo, useRef, useCallback } from "../vendor/hooks.js";
import htm from "../vendor/htm.js";

export const html = htm.bind(h);
export { render, Fragment, useState, useEffect, useMemo, useRef, useCallback };

/** "2026-10-31" for a date in the person's own time zone. */
export function dayKey(date = new Date()) {
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function parseDay(key) {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function addDays(key, days) {
  const d = parseDay(key);
  d.setDate(d.getDate() + days);
  return dayKey(d);
}

export const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2) + Date.now());

export const fmt = (n, digits = 0) =>
  Number(n || 0).toLocaleString(undefined, { maximumFractionDigits: digits, minimumFractionDigits: 0 });

export function dayTitle(key) {
  const today = dayKey();
  if (key === today) return "Today";
  if (key === addDays(today, -1)) return "Yesterday";
  if (key === addDays(today, 1)) return "Tomorrow";
  return parseDay(key).toLocaleDateString(undefined, { weekday: "long" });
}

export const longDate = (key) =>
  parseDay(key).toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });

export const ago = (iso) => { const t = relativeTime(iso); return t === "now" ? "just now" : `${t} ago`; };

export function relativeTime(iso) {
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (seconds < 60) return "now";
  const units = [["y", 31536000], ["w", 604800], ["d", 86400], ["h", 3600], ["m", 60]];
  for (const [u, s] of units) if (seconds >= s) return `${Math.floor(seconds / s)}${u}`;
  return "now";
}

/** Grams in a serving label such as "30 g" or "250 ml"; null when the label has no weight. */
export function gramsIn(serving) {
  const m = String(serving || "").match(/(\d+(?:[.,]\d+)?)\s*(g|ml)\b/i);
  return m ? parseFloat(m[1].replace(",", ".")) : null;
}

export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

export const number = (text) => {
  const v = parseFloat(String(text).replace(",", "."));
  return Number.isFinite(v) ? v : null;
};
