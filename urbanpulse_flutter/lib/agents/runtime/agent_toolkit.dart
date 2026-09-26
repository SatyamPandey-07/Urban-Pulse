import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';
import '../../services/data/ai_estimator.dart';
import '../../services/data/data_cache.dart';
import '../../services/data/forecast_client.dart';
import '../../services/data/geoapify_client.dart';
import '../../services/data/overpass_client.dart';
import '../../services/data/wikipedia_client.dart';
import '../../services/data/xotelo_client.dart';
import '../../services/place_geocoder.dart';
import '../tools/agent_tool.dart';
import '../tools/fetch_page_tool.dart';
import '../tools/web_search_tool.dart';
import 'agent_kind.dart';
import 'llm_pool.dart';

/// The tools and credit budget for ONE plan. A fresh budget per plan keeps a
/// single busy trip from spending a month of free-tier searches.
class PlanToolset {
  PlanToolset({required this.registry, required this.budget, required this.search, required this.fetch});

  final ToolRegistry registry;
  final ToolBudget budget;
  final WebSearchTool search;
  final FetchPageTool fetch;
}

/// Everything the planner's agents share: the model pool, the data clients,
/// the caches and the search providers. Built once from configuration; each
/// plan takes its own [PlanToolset]. Missing keys simply leave a provider out:
/// nothing here fails because a key is absent.
class AgentToolkit {
  AgentToolkit({
    required this.llm,
    required this.cache,
    required this.client,
    required this.xotelo,
    required this.overpass,
    required this.wikipedia,
    required this.forecast,
    required this.geocoder,
    required this.estimator,
    required this.tavily,
    this.geoapify,
  });

  final AgentLlm llm;
  final DataCache cache;
  final http.Client client;
  final XoteloClient xotelo;
  final GeoapifyClient? geoapify;
  final OverpassClient overpass;
  final WikipediaClient wikipedia;
  final ForecastClient forecast;
  final PlaceGeocoder geocoder;
  final AiEstimator estimator;

  /// Null when no Tavily key is configured.
  final TavilySearchProvider? tavily;

  /// Wires everything from the build-time configuration.
  factory AgentToolkit.fromConfig({SharedPreferences? prefs, http.Client? client, AgentLlm? llm}) {
    final http_ = client ?? http.Client();
    final DataCache cache = prefs == null ? MemoryCache() : PrefsCache(prefs);
    final pool = llm ?? LlmPool.fromConfig();
    final tavilyKeys = AppConfig.tavilyKeys;
    return AgentToolkit(
      llm: pool,
      cache: cache,
      client: http_,
      xotelo: XoteloClient(
        client: http_,
        cache: cache,
        rapidApiKey: AppConfig.hasXoteloRapidApiKey ? AppConfig.xoteloRapidApiKey : null,
      ),
      geoapify: AppConfig.hasGeoapifyKey
          ? GeoapifyClient(apiKey: AppConfig.geoapifyApiKey, client: http_, cache: cache)
          : null,
      overpass: OverpassClient(client: http_, cache: cache),
      wikipedia: WikipediaClient(client: http_, cache: cache),
      forecast: ForecastClient(client: http_, cache: cache),
      geocoder: PlaceGeocoder(client: http_),
      estimator: AiEstimator(pool),
      tavily: tavilyKeys.isEmpty ? null : TavilySearchProvider(keys: tavilyKeys, client: http_),
    );
  }

  /// Which data sources this build can actually use, for the UI and logs.
  Map<String, bool> get capabilities => {
    'groq': llm.isConfigured,
    'tavily': tavily?.available ?? false,
    'geoapify': geoapify?.isConfigured ?? false,
    'xoteloSearch': xotelo.canSearch,
    'xotelo': true,
    'overpass': true,
    'wikipedia': true,
  };

  /// A fresh set of tools with its own credit budget for one plan.
  PlanToolset newPlan({ToolBudget? budget}) {
    final b = budget ?? ToolBudget(maxSearches: 14, maxFetches: 12, maxLlmSearches: 6);
    final t = tavily;
    final search = WebSearchTool(
      budget: b,
      cache: cache,
      providers: [
        if (t != null) t,
        CompoundSearchProvider(llm: llm, agent: AgentKind.khoji, canSpend: b.trySpendLlmSearch),
        WikipediaSearchProvider(wikipedia),
      ],
    );
    final fetch = FetchPageTool(budget: b, tavily: t, client: client, cache: cache);
    final registry = ToolRegistry()
      ..register(search)
      ..register(fetch);
    return PlanToolset(registry: registry, budget: b, search: search, fetch: fetch);
  }
}
