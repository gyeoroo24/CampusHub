import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/error_text.dart';
import '../../../auth/domain/user.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';
import 'buy_sell_detail_dialog.dart';
import 'price_watch.dart' show NegotiableBadge;

/// Bookmarked Buy & Sell listings. Signed-in people's bookmarks live on their account; a guest's stay on
/// this device (browser storage or shared preferences) and move to the account when they sign in.
class _GuestListingBookmarks {
  static const _key = 'guest_listing_bookmarks';

  Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(Iterable<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, ids.toList());
    } catch (_) {
      // Storage unavailable (e.g. private browsing): bookmarks last for this session only.
    }
  }
}

bool _isGuest(User? user) => user == null || user.isGuest;

/// The ids of the listings bookmarked by whoever is using the app, newest last.
class ListingBookmarksNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;
  final _guestStore = _GuestListingBookmarks();
  User? _user;

  ListingBookmarksNotifier(this._ref) : super(const {}) {
    _user = _ref.read(currentUserProvider);
    _load();
    _ref.listen<User?>(currentUserProvider, (previous, next) {
      final signedIn = _isGuest(previous) && !_isGuest(next);
      _user = next;
      if (signedIn) {
        _importGuestBookmarks();
      } else if (previous?.id != next?.id) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    final user = _user;
    try {
      final ids = _isGuest(user)
          ? (await _guestStore.load()).toSet()
          : await _ref.read(buySellRepositoryProvider).fetchBookmarkedIds();
      if (mounted && identical(user, _user)) state = ids;
    } catch (_) {
      // Leave the current set; the next change of user tries again.
    }
  }

  /// Bookmarks made as a guest go to the account that just signed in, then leave the device.
  Future<void> _importGuestBookmarks() async {
    final ids = await _guestStore.load();
    if (ids.isNotEmpty) {
      try {
        await _ref.read(buySellRepositoryProvider).importBookmarks(ids);
        await _guestStore.save(const []);
      } catch (_) {
        // Keep them on the device and try again at the next sign-in.
      }
    }
    await _load();
    _ref.invalidate(bookmarkedListingsProvider);
  }

  /// Bookmark or un-bookmark [listingId]. Returns whether it is bookmarked now.
  Future<bool> toggle(String listingId) async {
    final on = !state.contains(listingId);
    final before = state;
    state = on ? {...state, listingId} : ({...state}..remove(listingId));
    try {
      if (_isGuest(_user)) {
        await _guestStore.save(state);
      } else {
        await _ref.read(buySellRepositoryProvider).setBookmarked(listingId, on);
      }
    } catch (_) {
      state = before;
      rethrow;
    }
    _ref.invalidate(bookmarkedListingsProvider);
    return on;
  }
}

final listingBookmarksProvider = StateNotifierProvider<ListingBookmarksNotifier, Set<String>>(
  (ref) => ListingBookmarksNotifier(ref),
);

/// The bookmarked listings themselves, most recently bookmarked first.
final bookmarkedListingsProvider = FutureProvider.autoDispose<List<ListingItem>>((ref) async {
  final user = ref.watch(currentUserProvider);
  final repo = ref.watch(buySellRepositoryProvider);
  if (!_isGuest(user)) return repo.fetchBookmarkedListings();
  final ids = ref.watch(listingBookmarksProvider).toList().reversed.toList();
  return repo.lookupListings(ids);
});

Future<void> _toggle(BuildContext context, WidgetRef ref, String listingId) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final on = await ref.read(listingBookmarksProvider.notifier).toggle(listingId);
    final guest = _isGuest(ref.read(currentUserProvider));
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(on
          ? (guest ? 'Bookmarked on this device. Sign in to keep it on your account.' : 'Bookmarked.')
          : 'Bookmark removed.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700));
  }
}

/// A round bookmark toggle laid over a listing photo.
class ListingBookmarkIcon extends ConsumerWidget {
  final String listingId;
  final double size;
  const ListingBookmarkIcon({super.key, required this.listingId, this.size = 18});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(listingBookmarksProvider).contains(listingId);
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _toggle(context, ref, listingId),
        child: Tooltip(
          message: on ? 'Remove bookmark' : 'Bookmark',
          child: Padding(
            padding: EdgeInsets.all(size * 0.33),
            child: Icon(on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                size: size, color: on ? Colors.amber.shade300 : Colors.white),
          ),
        ),
      ),
    );
  }
}

/// "Bookmark" button for the listing detail view.
class ListingBookmarkButton extends ConsumerWidget {
  final String listingId;
  const ListingBookmarkButton({super.key, required this.listingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(listingBookmarksProvider).contains(listingId);
    return OutlinedButton.icon(
      onPressed: () => _toggle(context, ref, listingId),
      icon: Icon(on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 18),
      label: Text(on ? 'Bookmarked' : 'Bookmark'),
    );
  }
}

/// The Buy & Sell toolbar's bookmarks list.
class BookmarkedListingsDialog extends ConsumerWidget {
  const BookmarkedListingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(bookmarkedListingsProvider);
    final ids = ref.watch(listingBookmarksProvider);
    final guest = _isGuest(ref.watch(currentUserProvider));
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.bookmarks_outlined),
        SizedBox(width: 10),
        Text('Bookmarks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (guest)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Saved on this device. Sign in to keep them on your account.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
              ),
            Flexible(
              child: listings.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text(errorText(e)),
                data: (all) {
                  // Hide ones un-bookmarked while the dialog is open.
                  final items = all.where((i) => ids.contains(i.id)).toList();
                  if (items.isEmpty) {
                    return const Text('No bookmarks yet. Tap the bookmark icon on a listing to save it here.');
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${item.status.label} • ${item.seller.name}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (item.negotiable) ...[const NegotiableBadge(), const SizedBox(width: 6)],
                          Text('₹${item.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            tooltip: 'Remove bookmark',
                            icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
                            onPressed: () => _toggle(context, ref, item.id),
                          ),
                        ]),
                        onTap: () => showDialog(context: context, builder: (_) => BuySellDetailDialog(item: item)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
