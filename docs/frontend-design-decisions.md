# CampusHub Frontend Design Decisions & Architecture Document

## 1. Codebase Structure: Feature-First (Modular) Architecture
* **Chosen Approach:** Feature-First (`lib/features/<module_name>/ui|data|providers`)
* **Alternatives Considered:**
  * **Layered / Clean Architecture (Domain-Driven Design):** Folder structure organized at root level by layer (`lib/domain/`, `lib/data/`, `lib/presentation/`).
  * **Package-by-Layer / Flat Structure:** Grouping all widgets in one folder, all models in another.
* **Rejection Reason:** Clean Architecture/DDD spreads a single business feature across multiple disconnected layers, creating heavy overhead, high token usage for LLM prompts, and merge conflict risks across team members. PRD requirements map directly to vertical student modules (Buy & Sell, Lost & Found, Academic Help, Placement Hub). Feature-First keeps UI, state providers, and mock/API data isolated per module, minimizing LLM context friction and simplifying peer code reviews.

---

## 2. State Management: Riverpod 2.x (Code Generation)
* **Chosen Approach:** Riverpod using `@riverpod` annotations and `riverpod_generator`.
* **Alternatives Considered:**
  * **BLoC / Cubit:** Event-driven state management framework.
  * **Provider:** Standard inherited widget wrapper.
  * **GetX / MobX:** Reactive state/route/dependency injection frameworks.
* **Rejection Reason:** BLoC requires substantial event, state, and mapper boilerplate, consuming token limits and slowing iteration. Provider lacks compile-time safety and automatic disposal mechanisms. GetX bypasses Flutter's widget tree using global state, leading to maintenance debt. Riverpod's `AsyncNotifier` with code generation handles `AsyncValue` data fetching states (`loading`, `data`, `error`) with minimal boilerplate—ideal for consuming FastAPI async endpoints.

---

## 3. Routing & Navigation: GoRouter
* **Chosen Approach:** `go_router` (Official Flutter package)
* **Alternatives Considered:**
  * **Navigator 1.0 / Raw Navigator 2.0:** Built-in Flutter imperative and declarative routers.
  * **AutoRoute:** Code-generation based routing library.
* **Rejection Reason:** Navigator 1.0 does not sync browser URLs natively on Flutter Web (e.g. `/buy-sell/item/123`), which is a core PRD target. Raw Navigator 2.0 requires extensive custom boilerplate. AutoRoute adds third-party macro dependencies. `go_router` natively handles web deep-linking, browser history, nested navigation layouts (`ShellRoute`), and global `redirect` guards for role-based authorization (Guest, Signed-in User, Moderator, Admin).

---

## 4. Network & API Layer: OpenAPI Generator CLI + Dio
* **Chosen Approach:** Auto-generated Dart client via `openapi-generator-cli` calling FastAPI's OpenAPI spec.
* **Alternatives Considered:**
  * **Manual `http`/`dio` Clients:** Hand-writing REST requests and `fromJSON`/`toJSON` deserializers.
  * **Retrofit for Flutter:** Annotation-based Dart REST client generator.
* **Rejection Reason:** Hand-written models and parsing logic introduce silent runtime bugs due to field name mismatches (e.g., `listing_id` vs `listingId`). Auto-generating the Dart client directly from FastAPI's live OpenAPI spec enforces contract-driven development, guarantees 100% type safety, and eliminates manual JSON mapping work.

---

## 5. Local Storage & Security: Hive + Flutter Secure Storage
* **Chosen Approach:** Hive for NoSQL object/list caching; `flutter_secure_storage` for JWT auth tokens.
* **Alternatives Considered:**
  * **`shared_preferences` alone:** Key-value string/int storage.
  * **SQLite / Sqflite / Isar:** Relational and NoSQL embedded databases.
* **Rejection Reason:** `shared_preferences` is slow for structured list data (like Guest bookmarked listings/events under FR-20). SQLite introduces native C library compilation setup on Web and Desktop. Hive is lightweight, fast, pure-Dart key-value/box storage that runs seamlessly across Web, Desktop, and Mobile. `flutter_secure_storage` encrypts sensitive Cognito JWT tokens at rest using Keychain/Keystore.
