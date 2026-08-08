import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  // Theme Colors
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
    final adminName = authProvider.adminModel?.firstname ?? "Admin";

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text(
          "MusicVerse Academy Admin",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications_outlined,
              color: textSecondary,
            ),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: CircleAvatar(
                backgroundColor: primaryColor,
                child: Text(
                  adminName.isNotEmpty ? adminName[0].toUpperCase() : "A",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              debugPrint('================================');
              debugPrint('LOGOUT BUTTON CLICKED');
              debugPrint('================================');

              try {
                debugPrint('LOGOUT STARTED');

                await fb.FirebaseAuth.instance.signOut();

                debugPrint('LOGOUT SUCCESSFUL');
                debugPrint('USER IS NOW LOGGED OUT');
                debugPrint('================================');

                if (context.mounted) {
                  context.go('/login');
                }
              } catch (e, stackTrace) {
                debugPrint('================================');
                debugPrint('LOGOUT FAILED');
                debugPrint('ERROR: $e');
                debugPrint('STACK TRACE:');
                debugPrint('$stackTrace');
                debugPrint('================================');
              }
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 900;
          return Row(
            children: [
              if (isDesktop)
                Container(
                  width: 250,
                  color: cardColor,
                  child: _buildSidebar(context),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Greeting
                      Text(
                        "Welcome back, $adminName",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Here is the overview of your academy's status today.",
                        style: TextStyle(color: textSecondary, fontSize: 14),
                      ),
                      const SizedBox(height: 24),

                      // Live Student Statistics Stream
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('user')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: primaryColor,
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return const Text(
                              "Unable to load student statistics.",
                              style: TextStyle(color: errorColor),
                            );
                          }

                          final docs = snapshot.data?.docs ?? [];
                          int totalStudents = docs.length;
                          int activeStudents = 0;
                          int inactiveStudents = 0;
                          int paidStudents = 0;
                          int pendingFees = 0;

                          for (var doc in docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            final accountStatus = data['accountStatus'] ?? '';
                            final feeStatus = data['feeStatus'] ?? '';

                            if (accountStatus == "Active") {
                              activeStudents++;
                            } else {
                              inactiveStudents++;
                            }

                            if (feeStatus == "Paid") {
                              paidStudents++;
                            } else {
                              pendingFees++;
                            }
                          }

                          return GridView.count(
                            crossAxisCount: constraints.maxWidth > 1200
                                ? 5
                                : (constraints.maxWidth > 700 ? 3 : 2),
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 1.5,
                            children: [
                              _buildStatCard(
                                "Total Students",
                                totalStudents.toString(),
                                primaryColor,
                                Icons.people,
                              ),
                              _buildStatCard(
                                "Active Students",
                                activeStudents.toString(),
                                successColor,
                                Icons.check_circle,
                              ),
                              _buildStatCard(
                                "Inactive Students",
                                inactiveStudents.toString(),
                                errorColor,
                                Icons.cancel,
                              ),
                              _buildStatCard(
                                "Paid Students",
                                paidStudents.toString(),
                                secondaryColor,
                                Icons.payment,
                              ),
                              _buildStatCard(
                                "Pending Fees",
                                pendingFees.toString(),
                                warningColor,
                                Icons.pending,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 32),

                      // Payment Summary Section
                      const Text(
                        "Payment Overview",
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
                          if (!snapshot.hasData) {
                            return const ContainerCard(
                              child: Text(
                                "Loading payments...",
                                style: TextStyle(color: textSecondary),
                              ),
                            );
                          }
                          final paymentDocs = snapshot.data!.docs;
                          int totalPaidPayments = paymentDocs
                              .where(
                                (d) =>
                                    (d.data()
                                        as Map<String, dynamic>)['status'] ==
                                    'Paid',
                              )
                              .length;
                          int totalPendingPayments =
                              paymentDocs.length - totalPaidPayments;

                          return ContainerCard(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildPaymentMetric(
                                  "Total Recorded Payments",
                                  paymentDocs.length.toString(),
                                  Colors.white,
                                ),
                                _buildPaymentMetric(
                                  "Paid Transactions",
                                  totalPaidPayments.toString(),
                                  successColor,
                                ),
                                _buildPaymentMetric(
                                  "Pending Transactions",
                                  totalPendingPayments.toString(),
                                  warningColor,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 32),

                      // Recent Students Section
                      const Text(
                        "Recent Students",
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
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: primaryColor,
                              ),
                            );
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return const ContainerCard(
                              child: Center(
                                child: Text(
                                  "No students found",
                                  style: TextStyle(color: textSecondary),
                                ),
                              ),
                            );
                          }

                          final studentDocs = snapshot.data!.docs;
                          return ContainerCard(
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: studentDocs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(color: Colors.white12),
                              itemBuilder: (context, index) {
                                final data =
                                    studentDocs[index].data()
                                        as Map<String, dynamic>;
                                final firstName = data['firstName'] ?? '';
                                final lastName = data['lastName'] ?? '';
                                final studentId = data['studentId'] ?? 'N/A';
                                final course = data['course'] ?? 'General';
                                final feeStatus =
                                    data['feeStatus'] ?? 'Pending';
                                final accountStatus =
                                    data['accountStatus'] ?? 'Inactive';
                                final profilePhoto = data['profilePhoto'] ?? '';

                                return ListTile(
                                  leading: profilePhoto.isNotEmpty
                                      ? CircleAvatar(
                                          backgroundImage: NetworkImage(
                                            profilePhoto,
                                          ),
                                        )
                                      : const CircleAvatar(
                                          backgroundColor: primaryColor,
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.white,
                                          ),
                                        ),
                                  title: Text(
                                    "$firstName $lastName",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "ID: $studentId • Course: $course",
                                    style: const TextStyle(
                                      color: textSecondary,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Chip(
                                        label: Text(
                                          feeStatus,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: feeStatus == 'Paid'
                                            ? primaryColor.withValues(
                                                alpha: 0.2,
                                              )
                                            : errorColor.withValues(alpha: 0.2),
                                      ),
                                      const SizedBox(width: 8),
                                      Chip(
                                        label: Text(
                                          accountStatus,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor:
                                            accountStatus == 'Active'
                                            ? primaryColor.withValues(
                                                alpha: 0.2,
                                              )
                                            : Colors.grey.withValues(
                                                alpha: 0.2,
                                              ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: textSecondary, fontSize: 13),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
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
    );
  }

  Widget _buildPaymentMetric(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(color: textSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(backgroundColor: cardColor, child: _buildSidebar(context));
  }

  Widget _buildSidebar(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const DrawerHeader(
          decoration: BoxDecoration(color: bgColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                "MusicVerse",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                "Admin Portal",
                style: TextStyle(color: primaryColor, fontSize: 14),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dashboard, color: primaryColor),
          title: const Text("Dashboard", style: TextStyle(color: Colors.white)),
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

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
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
