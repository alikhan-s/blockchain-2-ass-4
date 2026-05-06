export function StatusBadge({state}) {
    return <span className={`state-badge state-${state}`}>{state}</span>;
}
