import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../auth/providers/auth_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  // ============================================================
  // MUSICVERSE THEME
  // ============================================================

  static const Color bgColor = Color(0xFF0D1020);
  static const Color cardColor = Color(0xFF171C35);
  static const Color primaryColor = Color(0xFF7C4DFF);
  static const Color secondaryColor = Color(0xFF9D6BFF);
  static const Color successColor = Color(0xFF00E676);
  static const Color errorColor = Color(0xFFFF5252);
  static const Color warningColor = Color(0xFFFFC107);
  static const Color textSecondary = Color(0xFFB0B5D3);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    final adminName =
        authProvider.adminModel?.firstname.trim().isNotEmpty == true
        ? authProvider.adminModel!.firstname.trim()
        : 'Admin';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(context, adminName),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            final bool isVerySmall = width < 450;
            final bool isSmall = width < 700;
            // ignore: unused_local_variable
            final bool isMedium = width >= 700 && width < 1100;

            final double horizontalPadding = isVerySmall
                ? 12
                : isSmall
                ? 16
                : 24;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                30,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(adminName, isVerySmall, isSmall),

                  SizedBox(height: isVerySmall ? 18 : 26),

                  _buildStudentStatistics(context, constraints),

                  SizedBox(height: isVerySmall ? 22 : 30),

                  _buildPaymentOverview(context, constraints),

                  SizedBox(height: isVerySmall ? 22 : 30),

                  _buildRecentStudents(context, constraints),

                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // APP BAR
  // ============================================================

  PreferredSizeWidget _buildAppBar(BuildContext context, String adminName) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final bool isSmall = width < 600;

          return AppBar(
            backgroundColor: cardColor,
            elevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: isSmall ? 12 : 20,

            title: Row(
              children: [
                if (isSmall) ...[
                  const Icon(Icons.music_note, color: primaryColor, size: 22),
                  const SizedBox(width: 8),
                ],

                Flexible(
                  child: Text(
                    isSmall ? 'MusicVerse' : 'MusicVerse Academy Admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),

            actions: [
              IconButton(
                tooltip: 'Notifications',
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: textSecondary,
                ),
                onPressed: () {},
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: CircleAvatar(
                  radius: isSmall ? 18 : 20,
                  backgroundColor: primaryColor,
                  child: Text(
                    adminName.isNotEmpty ? adminName[0].toUpperCase() : 'A',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              IconButton(
                tooltip: 'Logout',
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () => _logout(context),
              ),

              const SizedBox(width: 6),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _logout(BuildContext context) async {
    try {
      debugPrint('LOGOUT STARTED');

      await fb.FirebaseAuth.instance.signOut();

      debugPrint('LOGOUT SUCCESSFUL');

      if (context.mounted) {
        context.go('/login');
      }
    } catch (e) {
      debugPrint('LOGOUT ERROR: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
      }
    }
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(String adminName, bool isVerySmall, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back, $adminName',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: isVerySmall
                ? 20
                : isSmall
                ? 23
                : 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          "Here is the overview of your academy's status today.",
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  // ============================================================
  // STUDENT STATISTICS
  // ============================================================

  Widget _buildStudentStatistics(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('user').snapshots(),

      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: CircularProgressIndicator(color: primaryColor),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorCard('Unable to load student statistics.');
        }

        final docs = snapshot.data?.docs ?? [];

        int totalStudents = 0;
        int activeStudents = 0;
        int inactiveStudents = 0;
        int paidStudents = 0;
        int pendingFees = 0;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;

          final accountStatus = data['accountStatus']?.toString() ?? '';

          final feeStatus = data['feeStatus']?.toString() ?? '';

          totalStudents++;

          if (accountStatus == 'Active') {
            activeStudents++;
          } else {
            inactiveStudents++;
          }

          if (feeStatus == 'Paid') {
            paidStudents++;
          } else {
            pendingFees++;
          }
        }

        // IMPORTANT:
        // Use the actual available Dashboard width.
        final width = constraints.maxWidth;

        int columns;

        if (width >= 1200) {
          columns = 5;
        } else if (width >= 900) {
          columns = 3;
        } else if (width >= 600) {
          columns = 2;
        } else {
          columns = 1;
        }

        final cards = [
          _buildStatCard(
            title: 'Total Students',
            value: totalStudents.toString(),
            color: primaryColor,
            icon: Icons.people_alt_outlined,
          ),
          _buildStatCard(
            title: 'Active Students',
            value: activeStudents.toString(),
            color: successColor,
            icon: Icons.check_circle_outline,
          ),
          _buildStatCard(
            title: 'Inactive Students',
            value: inactiveStudents.toString(),
            color: errorColor,
            icon: Icons.cancel_outlined,
          ),
          _buildStatCard(
            title: 'Paid Students',
            value: paidStudents.toString(),
            color: secondaryColor,
            icon: Icons.payment_outlined,
          ),
          _buildStatCard(
            title: 'Pending Fees',
            value: pendingFees.toString(),
            color: warningColor,
            icon: Icons.pending_outlined,
          ),
        ];

        // --------------------------------------------------------
        // VERY SMALL WIDTH
        // --------------------------------------------------------

        if (columns == 1) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                SizedBox(width: double.infinity, child: cards[i]),
                if (i != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        // --------------------------------------------------------
        // NORMAL DESKTOP/TABLET
        // --------------------------------------------------------

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),

          itemCount: cards.length,

          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,

            // Fixed minimum card height.
            // This prevents Bottom Overflow.
            mainAxisExtent: 112,
          ),

          itemBuilder: (context, index) {
            return cards[index];
          },
        );
      },
    );
  }

  // ============================================================
  // STAT CARD
  // ============================================================

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      height: 112,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),

      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: textSecondary, fontSize: 13),
                ),

                const SizedBox(height: 7),

                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Icon(icon, color: color, size: 22),
        ],
      ),
    );
  }

  // ============================================================
  // PAYMENT OVERVIEW
  // ============================================================

  Widget _buildPaymentOverview(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Overview',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('feePayments')
              .snapshots(),

          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ContainerCard(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return _buildErrorCard('Unable to load payment information.');
            }

            final paymentDocs = snapshot.data?.docs ?? [];

            int totalPaidPayments = 0;

            for (final doc in paymentDocs) {
              final data = doc.data() as Map<String, dynamic>;

              if (data['status'] == 'Paid') {
                totalPaidPayments++;
              }
            }

            final totalPendingPayments = paymentDocs.length - totalPaidPayments;

            final bool isSmall = constraints.maxWidth < 600;

            return ContainerCard(
              child: isSmall
                  ? Column(
                      children: [
                        _buildPaymentMetric(
                          'Total Recorded Payments',
                          paymentDocs.length.toString(),
                          Colors.white,
                        ),

                        const SizedBox(height: 20),

                        _buildPaymentMetric(
                          'Paid Transactions',
                          totalPaidPayments.toString(),
                          successColor,
                        ),

                        const SizedBox(height: 20),

                        _buildPaymentMetric(
                          'Pending Transactions',
                          totalPendingPayments.toString(),
                          warningColor,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _buildPaymentMetric(
                            'Total Recorded Payments',
                            paymentDocs.length.toString(),
                            Colors.white,
                          ),
                        ),

                        Expanded(
                          child: _buildPaymentMetric(
                            'Paid Transactions',
                            totalPaidPayments.toString(),
                            successColor,
                          ),
                        ),

                        Expanded(
                          child: _buildPaymentMetric(
                            'Pending Transactions',
                            totalPendingPayments.toString(),
                            warningColor,
                          ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ],
    );
  }

  // ============================================================
  // PAYMENT METRIC
  // ============================================================

  Widget _buildPaymentMetric(String title, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 5),

        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  // ============================================================
  // RECENT STUDENTS
  // ============================================================

  Widget _buildRecentStudents(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Students',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('user')
              .orderBy('createdAt', descending: true)
              .limit(5)
              .snapshots(),

          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: CircularProgressIndicator(color: primaryColor),
                ),
              );
            }

            if (snapshot.hasError) {
              return _buildErrorCard('Unable to load recent students.');
            }

            final studentDocs = snapshot.data?.docs ?? [];

            if (studentDocs.isEmpty) {
              return const ContainerCard(
                child: Center(
                  child: Text(
                    'No students found',
                    style: TextStyle(color: textSecondary),
                  ),
                ),
              );
            }

            return ContainerCard(
              child: Column(
                children: [
                  for (int i = 0; i < studentDocs.length; i++)
                    _buildStudentItem(
                      context,
                      studentDocs[i].data() as Map<String, dynamic>,
                      constraints,
                      i == studentDocs.length - 1,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ============================================================
  // STUDENT ITEM
  // ============================================================

  Widget _buildStudentItem(
    BuildContext context,
    Map<String, dynamic> data,
    BoxConstraints constraints,
    bool isLast,
  ) {
    final firstName = data['firstName']?.toString() ?? '';

    final lastName = data['lastName']?.toString() ?? '';

    final studentId = data['studentId']?.toString() ?? 'N/A';

    final course = data['course']?.toString() ?? 'General';

    final feeStatus = data['feeStatus']?.toString() ?? 'Pending';

    final accountStatus = data['accountStatus']?.toString() ?? 'Inactive';

    final profilePhoto = data['profilePhoto']?.toString() ?? '';

    final bool isSmall = constraints.maxWidth < 650;

    final fullName = '$firstName $lastName'.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfilePhoto(profilePhoto, fullName),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName.isEmpty ? 'Unnamed Student' : fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'ID: $studentId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Text(
                      'Course: $course',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              if (!isSmall) ...[
                const SizedBox(width: 8),

                _buildStatusChip(
                  feeStatus,
                  feeStatus == 'Paid' ? successColor : errorColor,
                ),

                const SizedBox(width: 8),

                _buildStatusChip(
                  accountStatus,
                  accountStatus == 'Active' ? successColor : Colors.grey,
                ),
              ],
            ],
          ),

          if (isSmall) ...[
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  feeStatus,
                  feeStatus == 'Paid' ? successColor : errorColor,
                ),

                _buildStatusChip(
                  accountStatus,
                  accountStatus == 'Active' ? successColor : Colors.grey,
                ),
              ],
            ),
          ],

          if (!isLast) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white12, height: 1),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // PROFILE PHOTO
  // ============================================================

  Widget _buildProfilePhoto(String profilePhoto, String fullName) {
    if (profilePhoto.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: primaryColor,

        child: ClipOval(
          child: Image.network(
            profilePhoto,
            width: 48,
            height: 48,
            fit: BoxFit.cover,

            errorBuilder: (context, error, stackTrace) {
              return _buildInitialAvatar(fullName);
            },
          ),
        ),
      );
    }

    return _buildInitialAvatar(fullName);
  }

  // ============================================================
  // INITIAL AVATAR
  // ============================================================

  Widget _buildInitialAvatar(String fullName) {
    String initials = 'S';

    final parts = fullName.trim().split(' ');

    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      initials = parts[0][0].toUpperCase();
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: primaryColor,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  // ============================================================
  // STATUS CHIP
  // ============================================================

  Widget _buildStatusChip(String text, Color color) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),

      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),

        borderRadius: BorderRadius.circular(7),

        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),

      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ============================================================
  // ERROR CARD
  // ============================================================

  Widget _buildErrorCard(String message) {
    return ContainerCard(
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: errorColor),

          const SizedBox(width: 10),

          Expanded(
            child: Text(message, style: const TextStyle(color: errorColor)),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// CONTAINER CARD
// ================================================================

class ContainerCard extends StatelessWidget {
  final Widget child;

  const ContainerCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: DashboardScreen.cardColor,

        borderRadius: BorderRadius.circular(14),
      ),

      child: child,
    );
  }
}
