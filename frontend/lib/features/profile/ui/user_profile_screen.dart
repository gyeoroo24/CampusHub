import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/phone_countries.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../auth/domain/user.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../../buy_sell/domain/buy_sell_item.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../../buy_sell/ui/widgets/buy_sell_detail_dialog.dart';
import '../../buy_sell/ui/widgets/edit_listing_dialog.dart';
import '../../lost_found/domain/lost_found_item.dart';
import '../../lost_found/providers/lost_found_providers.dart';
import '../../lost_found/ui/widgets/edit_report_dialog.dart';
import '../../lost_found/ui/widgets/lost_found_detail_dialog.dart';
import '../../wanted/providers/wanted_providers.dart';
import '../data/my_posts.dart';
import 'role_card.dart';
import 'verify_phone_dialog.dart';
import '../../wanted/ui/wanted_feed_sliver.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _isEditingProfile = false;
  bool _isSavingProfile = false;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  PhoneCountry _phoneCountry = india;
  final _programmeController = TextEditingController();
  final _gradYearController = TextEditingController();
  final _profileFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _populateFields(user);
  }

  void _populateFields(User? user) {
    if (user != null) {
      _nameController.text = user.name;
      final phone = splitPhone(user.phone);
      _phoneCountry = phone.country;
      _phoneController.text = phone.digits;
      _programmeController.text = user.programme ?? '';
      _gradYearController.text = user.graduationYear?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _programmeController.dispose();
    _gradYearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);

    // Guest prompt
    if (currentUser == null || currentUser.isGuest) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/buy'),
          ),
          title: const Text('My Profile'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              margin: const EdgeInsets.all(24),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.person_outline_rounded, size: 36, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Sign In to CampusHub',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please authenticate with your @iisc.ac.in credentials to view your profile, manage personal postings, and update contact settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.hintColor, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => AuthDialog.ensureSignedIn(context, ref),
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Sign In with IISc Email'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Campus',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/buy');
            }
          },
        ),
        title: const Text('My Profile & Postings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          if (currentUser.isAdmin)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              icon: const Icon(Icons.admin_panel_settings_rounded, size: 16),
              label: const Text('Admin Controls'),
              onPressed: () => context.push('/admin'),
            )
          else if (currentUser.isModerator)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.blue.shade700),
              icon: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('Moderator Panel'),
              onPressed: () => context.push('/moderator'),
            ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: () => _confirmSignOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Profile Overview Header ──
                _buildHeaderCard(currentUser, isDark, theme),
                const SizedBox(height: 20),

                // ── Role: admin tools or moderator roles (with Step down); nothing for students ──
                RoleCard(user: currentUser),

                // ── Edit Profile Form (collapsible) ──
                if (_isEditingProfile) ...[
                  _buildEditProfileCard(currentUser, isDark, theme),
                  const SizedBox(height: 20),
                ],

                // ── My Activity & Postings Hub ──
                _buildPostingsSection(currentUser, isDark, theme),

                // ── Account: only people can deactivate their own account (the admin hands the role over first) ──
                if (!currentUser.isAdmin) ...[
                  const SizedBox(height: 32),
                  _buildDeactivateCard(theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Profile Header Card
  // ---------------------------------------------------------------------------
  Widget _buildHeaderCard(User user, bool isDark, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    user.initials,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (user.isAdmin)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                            )
                          else if (user.isModerator)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('MODERATOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                            ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: user.isActive ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: user.isActive ? Colors.green.shade200 : Colors.red.shade200),
                            ),
                            child: Text(
                              user.isActive ? 'ACTIVE' : 'DEACTIVATED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: user.isActive ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: TextStyle(fontSize: 13, color: theme.hintColor),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (user.programme != null && user.programme!.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.school_outlined, size: 14, color: theme.hintColor),
                                const SizedBox(width: 4),
                                Text(user.programme!, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          if (user.graduationYear != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_available_outlined, size: 14, color: theme.hintColor),
                                const SizedBox(width: 4),
                                Text('Class of ${user.graduationYear}', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          if (user.phone != null && user.phone!.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_outlined, size: 14, color: theme.hintColor),
                                const SizedBox(width: 4),
                                Text(user.phone!, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isEditingProfile = !_isEditingProfile;
                        if (_isEditingProfile) _populateFields(user);
                      });
                    },
                    icon: Icon(_isEditingProfile ? Icons.close : Icons.edit_outlined, size: 14),
                    label: Text(_isEditingProfile ? 'Cancel' : 'Edit Profile', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),

          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit Profile Form Card
  // ---------------------------------------------------------------------------
  Widget _buildEditProfileCard(User user, bool isDark, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Update profile details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Form(
              key: _profileFormKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _nameController,
                    maxLength: 100,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: user.email,
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'IISc Email',
                      helperText: 'Your sign-in email can’t be changed',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<PhoneCountry>(
                    key: const Key('phone_country'),
                    initialValue: _phoneCountry,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Country',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    ),
                    selectedItemBuilder: (_) => [
                      for (final c in phoneCountries) Text('${c.flag} ${c.dialCode}', overflow: TextOverflow.ellipsis),
                    ],
                    items: [
                      for (final c in phoneCountries)
                        DropdownMenuItem(value: c, child: Text('${c.flag}  ${c.name} (${c.dialCode})')),
                    ],
                    onChanged: (c) {
                      if (c == null) return;
                      setState(() => _phoneCountry = c);
                      _profileFormKey.currentState?.validate();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: const Key('phone_number'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: _phoneCountry.maxDigits,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => _phoneCountry.check(v ?? ''),
                    decoration: InputDecoration(
                      labelText: 'Phone Number (Optional)',
                      hintText: _phoneCountry.minDigits == 10 ? 'e.g. 9876543210' : null,
                      helperText: 'A new number is verified with a code',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _programmeController,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: 'Degree Programme',
                      hintText: 'e.g. MTech CSA, PhD EECS',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _gradYearController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final year = int.tryParse(v.trim());
                      return (year == null || year < 1950 || year > 2100) ? 'A year between 1950 and 2100' : null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Graduation Year',
                      hintText: 'e.g. 2026',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
              ]),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSavingProfile ? null : _handleSaveProfile,
                icon: _isSavingProfile
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check, size: 16),
                label: const Text('Save Profile Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSaveProfile() async {
    // Same rules as the server, so a bad value is caught here instead of failing on save.
    if (!(_profileFormKey.currentState?.validate() ?? false)) return;
    final name = _nameController.text.trim();
    final digits = _phoneController.text.trim();
    final phone = digits.isEmpty ? '' : '${_phoneCountry.dialCode}$digits';
    final programme = _programmeController.text.trim();
    final gradYear = int.tryParse(_gradYearController.text.trim());
    final saved = ref.read(currentUserProvider)?.phone ?? '';
    final hadPhone = saved.isNotEmpty;

    // A new number only goes on the profile once its code is entered.
    if (phone.isNotEmpty && phone != saved) {
      final verified = await showVerifyPhoneDialog(context, phone);
      if (!verified || !mounted) return;
    }

    setState(() => _isSavingProfile = true);
    try {
      await ref.read(authRepositoryProvider).updateProfile(
            name: name,
            clearPhone: phone.isEmpty && hadPhone,
            programme: programme.isNotEmpty ? programme : null,
            graduationYear: gradYear,
          );
      ref.invalidate(currentUserProvider);
      setState(() => _isEditingProfile = false);
      _showToast('Profile updated successfully.');
    } catch (e) {
      _showToast('Failed to update profile: ${errorText(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Postings & Activity Hub Section
  // ---------------------------------------------------------------------------
  Widget _buildPostingsSection(User user, bool isDark, ThemeData theme) {
    // Moderators and the admin also see the companies and the events/mess menus they added.
    final tabs = <(String, Widget Function())>[
      ('Buy & Sell Listings', () => _buildMyBuySellList(user, isDark, theme)),
      ('Lost Reports', () => _buildMyLostReportsList(user, isDark, theme)),
      ('Found Reports', () => _buildMyFoundReportsList(user, isDark, theme)),
      ('Wanted Posts', _buildMyWantedList),
      ('Course Feedback', () => _buildMyPostsList((p) => p.feedback, Icons.rate_review_outlined,
          'No Course Feedback Yet', 'Feedback you leave on a course is listed here.')),
      ('Course Materials', () => _buildMyPostsList((p) => p.materials, Icons.description_outlined,
          'No Course Materials Yet', 'Notes, past papers and other files you share on a course are listed here.')),
      if (user.isModerator) ...[
        ('Placement Companies', () => _buildMyPostsList((p) => p.companies, Icons.business_outlined,
            'No Companies Added', 'Companies you add to the Placement Hub, by hand or from a CSV, are listed here.')),
        ('Events & Mess Menus', () => _buildMyPostsList((p) => p.events, Icons.event_outlined,
            'No Events or Menus Added', 'Events you create and mess menus you upload are listed here.')),
      ],
    ];
    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'My Postings Across Campus Modules',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'Review, edit details, update post statuses, or delete your own submissions across CampusHub.',
          style: TextStyle(fontSize: 12, color: theme.hintColor),
        ),
        const SizedBox(height: 12),

        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: theme.colorScheme.primary,
          tabs: [for (final t in tabs) Tab(text: t.$1)],
        ),
        const SizedBox(height: 16),

        SizedBox(
          height: 520,
          child: TabBarView(
            children: [for (final t in tabs) t.$2()],
          ),
        ),
      ],
      ),
    );
  }

  // ── Tab 1: My Buy & Sell Listings ──
  Widget _buildMyBuySellList(User user, bool isDark, ThemeData theme) {
    final listingsAsync = ref.watch(myBuySellListingsProvider);

    return listingsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState('No Buy & Sell listings yet.', 'Post items to sell or give away to fellow IISc students.');
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final item = items[idx];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: ListTile(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => BuySellDetailDialog(item: item),
                  );
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.coverPhotoUrl != null
                      ? Image.network(
                          item.coverPhotoUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.shopping_bag_outlined, size: 24),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.shopping_bag_outlined, size: 24),
                        ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₹${item.price.toInt()}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 14),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('${item.category.name} • ${item.location} • ${DateTimeFormatter.timeAgo(item.createdAt)}', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                    if (item.heldForReview) ...[
                      const SizedBox(height: 6),
                      // Stays until a moderator decides, so a missed notification doesn't leave the
                      // seller thinking buyers can see it.
                      Tooltip(
                        message: 'Flagged automatically as a possible prohibited item. Buyers can\'t see it '
                            'until a moderator reviews it.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hourglass_top_rounded, size: 12, color: Colors.orange.shade800),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text('Pending review · hidden from buyers',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade900)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final st in ListingStatus.values) ...[
                          ChoiceChip(
                            label: Text(st.label, style: const TextStyle(fontSize: 10)),
                            selected: item.status == st,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            onSelected: (selected) {
                              if (selected) {
                                ref.read(buySellRepositoryProvider).updateStatus(item.id, st);
                                ref.invalidate(myBuySellListingsProvider);
                                ref.read(buySellPaginationProvider.notifier).loadInitial();
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          tooltip: 'Edit Listing',
                          onPressed: () async {
                            final updated = await showDialog<bool>(
                              context: context,
                              builder: (_) => EditListingDialog(item: item),
                            );
                            if (updated == true) {
                              ref.invalidate(myBuySellListingsProvider);
                              ref.read(buySellPaginationProvider.notifier).loadInitial();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          tooltip: 'Delete Listing',
                          onPressed: () => _confirmDeleteListing(item),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error loading listings: ${errorText(e)}'),
    );
  }

  // ── Tab 2: My Lost Reports ──
  Widget _buildMyLostReportsList(User user, bool isDark, ThemeData theme) {
    final reportsAsync = ref.watch(myLostReportsProvider);

    return reportsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState('No lost reports filed.', 'If you lose an item on campus, report it here to match with finders.');
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final item = items[idx];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: ListTile(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => LostFoundDetailDialog(item: item),
                  );
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.coverPhotoUrl != null
                      ? Image.network(
                          item.coverPhotoUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.red.shade50,
                            child: const Icon(Icons.inventory_2_outlined, size: 24, color: Colors.red),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: Colors.red.shade50,
                          child: const Icon(Icons.inventory_2_outlined, size: 24, color: Colors.red),
                        ),
                ),
                title: Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('${item.category.name} • ${item.location} • ${DateTimeFormatter.timeAgo(item.createdAt)}', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final st in ReportStatus.values) ...[
                          ChoiceChip(
                            label: Text(st.label, style: const TextStyle(fontSize: 10)),
                            selected: item.status == st,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            onSelected: (selected) {
                              if (selected) {
                                ref.read(lostFoundRepositoryProvider).updateStatus(item.id, PostType.lost, st);
                                ref.invalidate(myLostReportsProvider);
                                ref.read(lostReportsPaginationProvider.notifier).loadInitial();
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          tooltip: 'Edit Report',
                          onPressed: () async {
                            final updated = await showDialog<bool>(
                              context: context,
                              builder: (_) => EditReportDialog(item: item),
                            );
                            if (updated == true) {
                              ref.invalidate(myLostReportsProvider);
                              ref.read(lostReportsPaginationProvider.notifier).loadInitial();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          tooltip: 'Delete Report',
                          onPressed: () => _confirmDeleteReport(item),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: ${errorText(e)}'),
    );
  }

  // ── Tab 3: My Found Reports ──
  Widget _buildMyFoundReportsList(User user, bool isDark, ThemeData theme) {
    final reportsAsync = ref.watch(myFoundReportsProvider);

    return reportsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState('No found reports filed.', 'Found an item on campus? Report it so the owner can recover it.');
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final item = items[idx];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: ListTile(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => LostFoundDetailDialog(item: item),
                  );
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.coverPhotoUrl != null
                      ? Image.network(
                          item.coverPhotoUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.teal.shade50,
                            child: const Icon(Icons.inventory_2_outlined, size: 24, color: Colors.teal),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: Colors.teal.shade50,
                          child: const Icon(Icons.inventory_2_outlined, size: 24, color: Colors.teal),
                        ),
                ),
                title: Text(
                  item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('${item.category.name} • ${item.location} • ${DateTimeFormatter.timeAgo(item.createdAt)}', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final st in ReportStatus.values) ...[
                          ChoiceChip(
                            label: Text(st.label, style: const TextStyle(fontSize: 10)),
                            selected: item.status == st,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            onSelected: (selected) {
                              if (selected) {
                                ref.read(lostFoundRepositoryProvider).updateStatus(item.id, PostType.found, st);
                                ref.invalidate(myFoundReportsProvider);
                                ref.read(foundReportsPaginationProvider.notifier).loadInitial();
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          tooltip: 'Edit Report',
                          onPressed: () async {
                            final updated = await showDialog<bool>(
                              context: context,
                              builder: (_) => EditReportDialog(item: item),
                            );
                            if (updated == true) {
                              ref.invalidate(myFoundReportsProvider);
                              ref.read(foundReportsPaginationProvider.notifier).loadInitial();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          tooltip: 'Delete Report',
                          onPressed: () => _confirmDeleteReport(item),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: ${errorText(e)}'),
    );
  }

  // ── Tab 4: My Wanted posts (open, fulfilled and closed) ──
  Widget _buildMyWantedList() {
    return ref.watch(myWantedPostsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load Wanted posts: ${errorText(e)}')),
          data: (posts) => posts.isEmpty
              ? _buildEmptyState(
                  'No Wanted Posts Yet',
                  'Switch Buy & Sell to "Wanted" to tell sellers what you are looking for.',
                )
              : ListView.separated(
                  itemCount: posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => SizedBox(height: 150, child: WantedCard(post: posts[i])),
                ),
        );
  }

  // ── Tabs 5 onwards: course feedback and materials; companies, events and mess menus (moderators) ──
  Widget _buildMyPostsList(List<MyPost> Function(MyPosts) pick, IconData icon, String emptyTitle, String emptyText) {
    return ref.watch(myPostsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load: ${errorText(e)}')),
          data: (all) {
            final posts = pick(all);
            if (posts.isEmpty) return _buildEmptyState(emptyTitle, emptyText);
            return RefreshIndicator(
              onRefresh: () => ref.refresh(myPostsProvider.future),
              child: ListView.separated(
                itemCount: posts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = posts[i];
                  return ListTile(
                    leading: Icon(icon),
                    title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(p.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Text(DateTimeFormatter.timeAgo(p.createdAt), style: const TextStyle(fontSize: 11)),
                    onTap: () => context.push(p.route),
                  );
                },
              ),
            );
          },
        );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteListing(ListingItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Listing?'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Listing'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(buySellRepositoryProvider).deleteListing(item.id);
      ref.invalidate(myBuySellListingsProvider);
      ref.read(buySellPaginationProvider.notifier).loadInitial();
      _showToast('Listing deleted.');
    }
  }

  Future<void> _confirmDeleteReport(LostFoundItem report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${report.kind == PostType.lost ? "Lost" : "Found"} Report?'),
        content: Text('Are you sure you want to delete this report?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Report'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(lostFoundRepositoryProvider).deleteReport(report.id, report.kind);
      if (report.kind == PostType.lost) {
        ref.invalidate(myLostReportsProvider);
        ref.read(lostReportsPaginationProvider.notifier).loadInitial();
      } else {
        ref.invalidate(myFoundReportsProvider);
        ref.read(foundReportsPaginationProvider.notifier).loadInitial();
      }
      _showToast('Report deleted.');
    }
  }

  Widget _buildDeactivateCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Deactivate my account',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                  const SizedBox(height: 4),
                  Text(
                    'You will be signed out. This is a suspension, not a deletion: your posts stay up with a '
                    '"Deactivated account" tag and nobody can message you, but you can reactivate it any time '
                    'by signing in again.',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
              onPressed: _confirmDeactivate,
              child: const Text('Deactivate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeactivate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate your account?'),
        content: const Text(
          'You will be signed out. Your listings, reports and wanted posts stay up with a "Deactivated '
          'account" tag, nobody can message you, and your moderator roles end.\n\n'
          'You can reactivate it any time by signing in again and confirming.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(apiClientProvider).post(ApiEndpoints.meDeactivate);
    } catch (e) {
      _showToast('Failed to deactivate your account: ${errorText(e)}', isError: true);
      return;
    }
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(currentUserProvider);
    if (mounted) context.go('/buy');
  }

  Future<void> _confirmSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out of CampusHub?'),
        content: const Text('You will be switched to a guest browsing session.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authRepositoryProvider).signOut();
      ref.invalidate(currentUserProvider);
      if (mounted) context.go('/buy');
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
