function normalizeBase(baseUrl: string): string {
  return baseUrl.replace(/\/+$/, "");
}

export async function bgLogin(
  baseUrl: string,
  email: string,
  password: string,
  deviceId: string,
  name = "Domino Chain PuryFi",
): Promise<{ token: string; device_id: string }> {
  const url = `${normalizeBase(baseUrl)}/api/auth/login`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email,
      password,
      device_id: deviceId,
      name,
    }),
  });
  const data = (await res.json().catch(() => ({}))) as {
    error?: string;
    token?: string;
    device_id?: string;
  };
  if (!res.ok) throw new Error(data.error || `Login failed (${res.status})`);
  if (!data.token || !data.device_id) throw new Error("Réponse login invalide");
  return { token: data.token, device_id: data.device_id };
}

export type PishockLevelSetting = {
  intensity: number;
  duration: number;
};

export type BgShowcaseSettings = {
  puryfi_min_score?: number;
  puryfi_seconds_per_label?: Record<string, number>;
  puryfi_shock_level_per_label?: Record<string, number>;
  puryfi_pishock_level_settings?: Record<string, PishockLevelSetting>;
};

export async function bgGetShowcaseSettings(
  baseUrl: string,
  pluginToken: string,
): Promise<{ ok: true; settings: BgShowcaseSettings } | { ok: false; error: string }> {
  const url = `${normalizeBase(baseUrl)}/api/showcase_settings`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${pluginToken}` },
  });
  const data = (await res.json().catch(() => ({}))) as BgShowcaseSettings & {
    error?: string;
  };
  if (!res.ok) {
    return {
      ok: false,
      error: data.error || res.statusText || `HTTP ${res.status}`,
    };
  }
  return {
    ok: true,
    settings: {
      puryfi_min_score: data.puryfi_min_score,
      puryfi_seconds_per_label: data.puryfi_seconds_per_label,
      puryfi_shock_level_per_label: data.puryfi_shock_level_per_label,
      puryfi_pishock_level_settings: data.puryfi_pishock_level_settings,
    },
  };
}

export async function bgAddTime(
  baseUrl: string,
  token: string,
  seconds: number,
  deviceId?: string,
): Promise<{ ok: boolean; added_seconds?: number; error?: string }> {
  const url = `${normalizeBase(baseUrl)}/api/chaster/add_time`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
  if (deviceId) headers["X-Device-Id"] = deviceId;
  const res = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ seconds }),
  });
  const data = (await res.json().catch(() => ({}))) as {
    ok?: boolean;
    added_seconds?: number;
    error?: string;
  };
  if (!res.ok) return { ok: false, error: data.error || res.statusText };
  return { ok: true, added_seconds: data.added_seconds };
}

export async function bgPishockShock(
  baseUrl: string,
  token: string,
  intensity: number,
  duration: number,
): Promise<{ ok: boolean; error?: string }> {
  const url = `${normalizeBase(baseUrl)}/api/pishock/shock`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ intensity, duration }),
  });
  const data = (await res.json().catch(() => ({}))) as {
    ok?: boolean;
    error?: string;
  };
  if (!res.ok) return { ok: false, error: data.error || res.statusText };
  return { ok: true };
}
