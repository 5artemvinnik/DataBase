// Допоміжні функції для вимірювання швидкості запитів (підключаються через load()).

// Виконує запит runs разів і повертає медіану часу (мс) та статистику плану.
function bench(coll, filter, opts = {}) {
  const runs = opts.runs || 9;
  const make = () => {
    let c = db[coll].find(filter, opts.projection || {});
    if (opts.sort) c = c.sort(opts.sort);
    if (opts.limit) c = c.limit(opts.limit);
    if (opts.hint) c = c.hint(opts.hint);
    return c;
  };
  make().toArray();                                   // «прогрів» кешу
  const times = [];
  for (let i = 0; i < runs; i++) {
    const t = performance.now();
    make().toArray();
    times.push(performance.now() - t);
  }
  times.sort((a, b) => a - b);
  const ex = make().explain("executionStats");
  const stages = [];
  (function walk(s) { if (!s) return; stages.push(s.stage + (s.indexName ? "(" + s.indexName + ")" : ""));
                      walk(s.inputStage); (s.inputStages || []).forEach(walk); })(ex.queryPlanner.winningPlan.queryPlan || ex.queryPlanner.winningPlan);
  return {
    plan: stages.join(" <- "),
    returned: ex.executionStats.nReturned,
    keysExamined: ex.executionStats.totalKeysExamined,
    docsExamined: ex.executionStats.totalDocsExamined,
    median_ms: Math.round(times[Math.floor(runs / 2)] * 100) / 100
  };
}

// Зберігає результат вимірювання в колекцію perf_results для порівняння «до/після».
function record(stage, name, r) {
  db.perf_results.updateOne({ stage, name }, { $set: { ...r, measured_at: new Date() } }, { upsert: true });
  return r;
}

// Таблиця порівняння «до/після» для заданих запитів.
function compare(names) {
  return names.map(n => {
    const b = db.perf_results.findOne({ stage: "before", name: n });
    const a = db.perf_results.findOne({ stage: "after", name: n });
    return { query: n, before_ms: b.median_ms, after_ms: a.median_ms,
             docs_before: b.docsExamined, docs_after: a.docsExamined,
             speedup: Math.round(b.median_ms / Math.max(a.median_ms, 0.01) * 10) / 10 + "x" };
  });
}
