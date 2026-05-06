export function shortAddress(addr) {
    if (!addr) return "—";
    return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function formatNumber(value, fractionDigits = 2) {
    if (value === null || value === undefined) return "—";
    const num = typeof value === "string" ? Number(value) : value;
    if (!Number.isFinite(num)) return "—";
    return new Intl.NumberFormat("en-US", {
        maximumFractionDigits: fractionDigits,
    }).format(num);
}
