import Foundation

var failures: [String] = []
func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

// ── 模型榜引擎（ModelLeaderboardEngine） ──────────────────────────────────

let fixtureJSON = #"""
{"data":[
  {"id":"openai/gpt-5.1-codex-max","name":"OpenAI: GPT-5.1-Codex-Max","created":1767225600,
   "context_length":400000,"pricing":{"prompt":"0.00001","completion":"0.00004"}},
  {"id":"deepseek/deepseek-v4.1-flash-1017","name":"DeepSeek: DeepSeek V4.1 Flash 1017","created":1766352000,
   "context_length":131072,"pricing":{"prompt":"0.00000015","completion":"0.0000006"}},
  {"id":"somevendor/old-model","name":"Old: Model","created":1700000000,
   "context_length":8192,"pricing":{"prompt":"0.000001","completion":"0.000002"}},
  {"id":"google/gemini-2.0-flash","name":"Google: Gemini 2.0 Flash","created":1700000000,
   "context_length":1048576,"pricing":{"prompt":"0.0000001","completion":"0.0000004"}},
  {"id":"somevendor/free-model","name":"Free: Model","created":1766352000,
   "context_length":262144,"pricing":{"prompt":"0","completion":"0"}},
  {"id":"google/gemini-4-argon","name":"Google: Gemini 4 Argon","created":1766352000,
   "context_length":1048576,"pricing":{"prompt":"0.000002","completion":"0.00001","image":"0.000002"},
   "architecture":{"output_modalities":["text"]}},
  {"id":"google/nano-banana-pro","name":"Nano Banana Pro (Gemini 3 Pro Image)","created":1766352000,
   "context_length":65536,"pricing":{"prompt":"0.000002","completion":"0.000012","image":"0.02"},
   "architecture":{"output_modalities":["image"]}},
  {"id":"openai/gpt-5.1-codex-max:batch","name":"OpenAI: GPT-5.1-Codex-Max (batch)","created":1766352000,
   "context_length":400000,"pricing":{"prompt":"0.000005","completion":"0.00002"}}
]}
"""#

let models = try! JSONDecoder().decode(OpenRouterModelsResponse.self, from: Data(fixtureJSON.utf8)).data
check(models.count == 8, "fixture decodes 8 models")

// 1. 能力分：最长子串命中；新一代旗舰居首
check(ModelLeaderboardEngine.capabilityOf("deepseek/deepseek-v4.1-flash-1017") == 90,
      "capabilityOf: longest substring wins (deepseek-v4.1 = 90 after 2026-10-25 rescale)")
check(ModelLeaderboardEngine.capabilityOf("openai/gpt-6.1-sol-pro") == 100,
      "capabilityOf: gpt-6.1-sol-pro = 100 (2026-10-25 代际更新后居首)")
check(ModelLeaderboardEngine.capabilityOf("openai/gpt-5.1-codex-max") == 96,
      "capabilityOf: gpt-5.1-codex-max demoted to 96")
check(ModelLeaderboardEngine.capabilityOf("anthropic/claude-opus-5.5") == 99,
      "capabilityOf: claude-opus-5.5 = 99")
check(ModelLeaderboardEngine.capabilityOf("somevendor/old-model") == nil,
      "capabilityOf: unknown model has no score")
check(ModelLeaderboardEngine.capabilityOf("google/gemini-2.0-flash") == 79,
      "capabilityOf: old-but-scored model keeps its score")

// 2. 混合单价 = 0.75×输入 + 0.25×输出（$/M）
check(abs(ModelLeaderboardEngine.perMillion("0.000002") - 2.0) < 1e-9, "perMillion converts per-token to per-M")
let gpt = models.first { $0.id == "openai/gpt-5.1-codex-max" }!
let blended = ModelLeaderboardEngine.perMillion(gpt.pricing?.prompt) * 0.75
    + ModelLeaderboardEngine.perMillion(gpt.pricing?.completion) * 0.25
check(abs(blended - 17.5) < 1e-9, "blended price: 0.75×10 + 0.25×40 = 17.5")

// 3. 价格文本
check(ModelLeaderboardEngine.priceText(4.0) == "$4.00", "priceText: >=1 uses two decimals")
check(ModelLeaderboardEngine.priceText(0.074) == "$0.074", "priceText: sub-dollar uses three decimals")
check(ModelLeaderboardEngine.priceText(0.00012) == "$0.00012", "priceText: tiny uses five decimals")
check(ModelLeaderboardEngine.priceText(0) == "免费", "priceText: zero is 免费")

// 4. 上下文文本
check(ModelLeaderboardEngine.contextText(1_048_576) == "1M", "contextText: >=1M")
check(ModelLeaderboardEngine.contextText(200_000) == "195K", "contextText: K divides by 1024")
check(ModelLeaderboardEngine.contextText(0) == "—", "contextText: missing")

// 5. 排序（now 取 fixture 中最新模型 +1 天，保证窗口一致）
let now = Date(timeIntervalSince1970: 1767312000)
let snapshot = ModelLeaderboardEngine.rank(models: models, now: now, limit: 40)

check(snapshot.totalCount == 8, "snapshot counts all models")
check(snapshot.freeCount == 1, "snapshot counts the free model")
check(snapshot.paidCount == 7, "snapshot counts paid models")

// 雷达：30 天窗口内 5 个，old-model（2023-11）被排除
check(snapshot.radarCount == 6, "radar excludes models older than 30 days")
let radarIDs = snapshot.rows(.radar).map(\.modelID)
check(!radarIDs.contains("somevendor/old-model"), "radar: old model excluded")
check(radarIDs.first == "openai/gpt-5.1-codex-max", "radar: newest first")
check(snapshot.rows(.radar).first?.noteText.contains("上线") == true, "radar row notes launch date")

// 能力榜：图像输出模型与 batch 变体被过滤；多模态文本模型（带 image 输入价）必须保留
let capIDs = snapshot.rows(.capability).map(\.modelID)
check(capIDs.first == "google/gemini-4-argon", "capability: top is Gemini 4 Argon (98, multimodal not excluded)")
check(!capIDs.contains("google/nano-banana-pro"), "capability: image-output model excluded")
check(capIDs.contains("google/gemini-4-argon"),
      "capability: multimodal text model with image input pricing is NOT excluded (2026-10-25 fix)")
check(!capIDs.contains("openai/gpt-5.1-codex-max:batch"), "capability: batch variant excluded")
check(capIDs.contains("deepseek/deepseek-v4.1-flash-1017"), "capability: deepseek v4.1 flash included")
check(capIDs.contains("google/gemini-2.0-flash"), "capability: old scored model still listed")

// 性价比榜：免费不进；旧模型（>180 天）也不进，避免旧低价霸榜。
let valueRows = snapshot.rows(.value)
check(valueRows.count == 3, "value: only recent scored+paid models (3 expected), got \(valueRows.count)")
check(!valueRows.contains { $0.modelID == "somevendor/free-model" }, "value: free model excluded")
check(!valueRows.contains { $0.modelID == "google/gemini-2.0-flash" },
      "value: old scored model excluded (kept in capability/price instead)")
check(valueRows.first?.modelID == "deepseek/deepseek-v4.1-flash-1017", "value: deepseek flash tops (matches Python run)")
check(abs((valueRows.first?.valueIndex ?? 0) - 100) < 0.5, "value: top index is 100")

// 价格榜：保留旧模型；免费在最便宜收费之后单列（低价在前）。
let priceRows = snapshot.rows(.price)
check(priceRows.first?.modelID == "google/gemini-2.0-flash", "price: cheapest paid first ($0.175 blended, old model still listed)")
check(priceRows.last?.modelID == "somevendor/free-model", "price: free models listed after paid")

// 6. 缓存编解码 round-trip
let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
let data = try! encoder.encode(snapshot)
let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
let decoded = try! decoder.decode(LeaderboardSnapshot.self, from: data)
check(decoded == snapshot, "snapshot survives Codable round-trip")

// 7. 空输入
let empty = ModelLeaderboardEngine.rank(models: [], now: now)
check(empty.totalCount == 0 && empty.boards.allSatisfy { $0.rows.isEmpty }, "empty input yields empty snapshot")

// 8. rankings 页面解析器：RSC 提取 → AA 指数 + 用量
let rankingsFixtureHTML = """
<script>self.__next_f.push([1,"7:[\"aaData\":{\"intelligence\":[{\"uid\":\"openai/gpt-6.1-sol-pro-20260929\",\"permaslug\":\"openai/gpt-6.1-sol-pro-20260929\",\"openrouter_slug\":null,\"heuristic_openrouter_slug\":\"openai/gpt-6.1-sol-pro\",\"aa_name\":\"GPT-6.1 Sol Pro\",\"score\":57.6}]}"])</script>
<script>self.__next_f.push([1,"8:[{\"date\":\"2026-10-24 00:00:00\",\"model_permaslug\":\"openai/gpt-6.1-sol-pro\",\"variant\":\"standard\",\"total_completion_tokens\":100,\"total_prompt_tokens\":200,\"count\":5,\"change\":12.5}]"])</script>
"""
let parsed = LeaderboardRankingsParser.supplement(fromHTML: rankingsFixtureHTML)
check(parsed != nil, "parser: RSC fixture decodes")
check(parsed?.aaScores["openai/gpt-6.1-sol-pro"] == 57.6, "parser: AA score extracted")
check(parsed?.usage["openai/gpt-6.1-sol-pro"]?.tokens == 300, "parser: usage tokens summed (prompt+completion)")
check(parsed?.usage["openai/gpt-6.1-sol-pro"]?.change == 12.5, "parser: usage change extracted")
check(parsed?.usageDate == "2026-10-24 00:00:00", "parser: usage date captured")
check(LeaderboardRankingsParser.supplement(fromHTML: "<html>nothing here</html>") == nil, "parser: garbage HTML yields nil")

// 9. AA 优先 + 缩放：静态分按 AA 顶格等比缩放，混排可比
let supplement = LeaderboardSupplement(
    aaScores: ["openai/gpt-5.1-codex-max": 60.0, "google/gemini-4-argon": 50.0],
    usage: ["deepseek/deepseek-v4.1-flash-1017": (tokens: 12_000_000_000_000, change: 44.2)],
    usageDate: "2026-10-24 00:00:00"
)
let merged = ModelLeaderboardEngine.rank(models: models, supplement: supplement, now: now)
check(merged.aaCount == 2, "merged: aaCount counts AA-covered models")
let mergedCap = merged.rows(.capability)
check(mergedCap.first?.modelID == "openai/gpt-5.1-codex-max", "merged: AA 60 beats scaled-static top (90×0.6=54)")
check(mergedCap.first?.scoreText == "60.0", "merged: AA score shows one decimal")
// deepseek 静态 90 × 0.6 = 54，仍应入榜且显示取整
let deepseekRow = mergedCap.first { $0.modelID == "deepseek/deepseek-v4.1-flash-1017" }
check(deepseekRow != nil && deepseekRow?.aaScore == nil, "merged: static-only model still listed, marked as non-AA")
check(deepseekRow?.scoreText == "54", "merged: static score scaled and rounded, got \(deepseekRow?.scoreText ?? "nil")")

// 10. 热度榜：按 token 用量降序，注释带环比
let popularity = merged.rows(.popularity)
check(popularity.count == 1, "popularity: only models with usage data")
check(popularity.first?.modelID == "deepseek/deepseek-v4.1-flash-1017", "popularity: the one with usage")
check(popularity.first?.noteText.contains("↑44%") == true, "popularity: change arrow, got \(popularity.first?.noteText ?? "nil")")
check(ModelLeaderboardEngine.tokenText(12_000_000_000_000) == "12.0T", "tokenText: trillions")
check(ModelLeaderboardEngine.tokenText(3_400_000_000) == "3B", "tokenText: billions")

// 11. 无 supplement 时回退纯静态表（降级路径）
let fallback = ModelLeaderboardEngine.rank(models: models, supplement: nil, now: now)
check(fallback.aaCount == 0, "fallback: no AA data")
check(fallback.rows(.capability).first?.scoreText == "98", "fallback: static table tops at 98 (Gemini 4 Argon)")
check(fallback.rows(.popularity).isEmpty, "fallback: no popularity board without usage data")

if failures.isEmpty {
    print("Model leaderboard tests passed")
} else {
    print(failures.joined(separator: "\n"))
    exit(1)
}
