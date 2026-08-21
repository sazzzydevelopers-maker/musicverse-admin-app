import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

class PaymentDashboardScreen extends StatefulWidget {
  const PaymentDashboardScreen({super.key});

  @override
  State<PaymentDashboardScreen> createState() => _PaymentDashboardScreenState();
}

class _PaymentDashboardScreenState extends State<PaymentDashboardScreen> {
  // Automatically opens on the user's current month.
  // Example: if the current month is October 2026, it opens on October 2026.
  final DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _selectedStatusFilter = 'All';

  // Added: prevents duplicate current-month fee records while the live streams refresh.
  bool _isSyncingCurrentMonthPayments = false;

  // Theme Constants matching MusicVerse Academy
  static const Color bgColor = Color(0xFF0D1020);
  static const Color cardColor = Color(0xFF171C35);
  static const Color primaryColor = Color(0xFF7C4DFF);
  static const Color secondaryColor = Color(0xFF9D6BFF);
  static const Color successColor = Color(0xFF00E676);
  static const Color errorColor = Color(0xFFFF5252);
  static const Color textSecondary = Color(0xFFB0B5D3);
  static const Color warningColor = Color(0xFFFFC107);

  // Change this one value in the future if the academy name changes.
  static const String academyName = 'MusicVerse Academy';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  DateTime? _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool _isPaidForSelectedMonth(Map<String, dynamic>? payment) {
    if (payment == null) return false;

    final status = (payment['status'] ?? '').toString().toLowerCase();
    final date = _timestampToDate(payment['paymentDate']);
    final paymentMonth = (payment['paymentMonth'] ?? '')
        .toString()
        .toLowerCase();
    final paymentYear = payment['paymentYear']?.toString() ?? '';

    final matchesDate =
        date != null &&
        date.year == _selectedMonth.year &&
        date.month == _selectedMonth.month;

    final matchesFields =
        paymentMonth == _getMonthName(_selectedMonth.month).toLowerCase() &&
        paymentYear == _selectedMonth.year.toString();

    return status == 'paid' && (matchesDate || matchesFields);
  }

  bool _isOverdue(Map<String, dynamic> student, Map<String, dynamic>? payment) {
    if (_isPaidForSelectedMonth(payment)) return false;

    final dueDate =
        _timestampToDate(payment?['nextDueDate']) ??
        _timestampToDate(student['nextDueDate']);

    if (dueDate != null) {
      return DateTime.now().isAfter(dueDate);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text(
          "Payment Management",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh",
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }

          if (userSnapshot.hasError) {
            return const Center(
              child: Text(
                "Unable to load student records.",
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final students = (userSnapshot.data?.docs ?? []).where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final role = (data['role'] ?? 'student')
                .toString()
                .trim()
                .toLowerCase();
            return role.isEmpty || role == 'student';
          }).toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('feePayments')
                .snapshots(),
            builder: (context, paymentSnapshot) {
              if (paymentSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: primaryColor),
                );
              }

              if (paymentSnapshot.hasError) {
                return const Center(
                  child: Text(
                    "Unable to load payment records.",
                    style: TextStyle(color: errorColor),
                  ),
                );
              }

              final paymentDocs = paymentSnapshot.data?.docs ?? [];
              final Map<String, Map<String, dynamic>> currentPayments = {};

              // Added: keep feePayments complete for the current month.
              // Missing current-month records are created automatically as Not Paid.
              _scheduleCurrentMonthPaymentSync(students, paymentDocs);

              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, searchValue, child) {
                  final searchQuery = searchValue.text.trim().toLowerCase();

                  double totalRevenue = 0;
                  for (final doc in paymentDocs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final status = (data['status'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();

                    if (status == 'paid') {
                      final amount = data['amountPaid'] is num
                          ? (data['amountPaid'] as num).toDouble()
                          : data['monthlyFee'] is num
                          ? (data['monthlyFee'] as num).toDouble()
                          : 0.0;
                      totalRevenue += amount;
                    }
                  }

                  for (final doc in paymentDocs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final uid = (data['uid'] ?? '').toString().trim();
                    final studentId = (data['studentId'] ?? '')
                        .toString()
                        .trim();

                    final paymentDate = _timestampToDate(data['paymentDate']);
                    final month = (data['paymentMonth'] ?? '')
                        .toString()
                        .toLowerCase();
                    final year = data['paymentYear']?.toString() ?? '';

                    final matchesDate =
                        paymentDate != null &&
                        paymentDate.year == _selectedMonth.year &&
                        paymentDate.month == _selectedMonth.month;

                    final matchesFields =
                        month ==
                            _getMonthName(_selectedMonth.month).toLowerCase() &&
                        year == _selectedMonth.year.toString();

                    if (matchesDate || matchesFields) {
                      final paymentWithId = {...data, 'docId': doc.id};

                      // Support both uid and studentId so older feePayment
                      // documents are still linked correctly.
                      if (uid.isNotEmpty) {
                        currentPayments[uid] = paymentWithId;
                      }
                      if (studentId.isNotEmpty) {
                        currentPayments[studentId] = paymentWithId;
                      }
                    }
                  }

                  double monthlyIncome = 0;
                  int paidCount = 0;
                  int pendingCount = 0;
                  int pendingStatusCount = 0;
                  int notPaidCount = 0;
                  int overdueCount = 0;
                  double pendingAmount = 0;

                  // Added: total expected fees for every student in the selected month.
                  double totalFees = 0;

                  final List<Map<String, dynamic>> filteredList = [];

                  for (final studentDoc in students) {
                    final student = studentDoc.data() as Map<String, dynamic>;

                    final uid = (student['uid'] ?? studentDoc.id).toString();
                    final studentId = _getStudentId(student);

                    final payment =
                        currentPayments[uid] ??
                        (studentId == 'Not assigned'
                            ? null
                            : currentPayments[studentId]);

                    final paid = _isPaidForSelectedMonth(payment);
                    final overdue = _isOverdue(student, payment);

                    final fee = payment != null && payment['monthlyFee'] is num
                        ? (payment['monthlyFee'] as num).toDouble()
                        : student['monthlyFee'] is num
                        ? (student['monthlyFee'] as num).toDouble()
                        : 0.0;

                    // Added: every active student contributes their expected
                    // monthly fee to Total Fees for the selected month.
                    totalFees += fee;

                    if (paid) {
                      monthlyIncome += payment?['amountPaid'] is num
                          ? (payment?['amountPaid'] as num).toDouble()
                          : fee;
                      paidCount++;
                    } else {
                      // Pending Fees remains the total number of unpaid students.
                      pendingCount++;
                      pendingAmount += fee;

                      final storedStatus = (payment?['status'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();

                      if (overdue || storedStatus == 'overdue') {
                        overdueCount++;
                      } else if (storedStatus == 'pending') {
                        pendingStatusCount++;
                      } else {
                        notPaidCount++;
                      }
                    }

                    final studentName = _studentDisplayName(student);

                    final searchText =
                        '$studentName '
                                '$uid '
                                '${student['course'] ?? ''} '
                                '${student['courseName'] ?? ''} '
                                '${student['course_name'] ?? ''} '
                                '${student['preferredInstrument'] ?? ''} '
                                '${student['preferred_instrument'] ?? ''} '
                                '${student['phone'] ?? ''} '
                                '${student['phoneNumber'] ?? ''} '
                                '${student['phone_number'] ?? ''}'
                            .toLowerCase();

                    final matchesSearch =
                        searchQuery.isEmpty || searchText.contains(searchQuery);

                    final storedStatus = (payment?['status'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();

                    final displayStatus = paid
                        ? 'Paid'
                        : storedStatus == 'pending'
                        ? 'Pending'
                        : storedStatus == 'not paid'
                        ? 'Not Paid'
                        : overdue
                        ? 'Overdue'
                        : 'Not Paid';

                    final matchesStatus =
                        _selectedStatusFilter == 'All' ||
                        displayStatus.toLowerCase() ==
                            _selectedStatusFilter.toLowerCase();

                    if (matchesSearch && matchesStatus) {
                      filteredList.add({
                        ...student,
                        'docId': studentDoc.id,
                        'uid': uid,
                        'studentName': studentName.isEmpty
                            ? 'Unknown Student'
                            : studentName,
                        'monthlyFee': fee,
                        'payment': payment,
                        'displayStatus': displayStatus,
                      });
                    }
                  }

                  final totalStudents = students.length;

                  final collectionRate = totalStudents > 0
                      ? (paidCount / totalStudents) * 100
                      : 0.0;

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: SingleChildScrollView(
                      key: ValueKey(
                        '${_selectedMonth.year}-${_selectedMonth.month}-'
                        '$_selectedStatusFilter',
                      ),
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  "Track academy revenue, payments and outstanding fees.",
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Existing KPI cards preserved.
                          GridView.count(
                            crossAxisCount:
                                MediaQuery.of(context).size.width > 1200
                                ? 4
                                : (MediaQuery.of(context).size.width > 700
                                      ? 2
                                      : 1),
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: 2.2,
                            children: [
                              _buildKpiCard(
                                "Monthly Income",
                                "₹${monthlyIncome.toStringAsFixed(0)}",
                                "${_getMonthName(_selectedMonth.month)} "
                                    "${_selectedMonth.year}",
                                successColor,
                                Icons.account_balance_wallet,
                              ),
                              _buildKpiCard(
                                "Total Collected",
                                "$paidCount Payments",
                                "Paid records count",
                                primaryColor,
                                Icons.check_circle,
                              ),
                              _buildKpiCard(
                                "Pending Fees",
                                "₹${pendingAmount.toStringAsFixed(0)}",
                                "$pendingCount unpaid records",
                                errorColor,
                                Icons.warning_amber,
                              ),
                              _buildKpiCard(
                                "Collection Rate",
                                "${collectionRate.toStringAsFixed(1)}%",
                                "Overall efficiency",
                                secondaryColor,
                                Icons.analytics,
                              ),
                            ],
                          ),

                          // Added financial summary cards.
                          // The original KPI cards above are unchanged.
                          const SizedBox(height: 16),
                          _buildFinancialSummarySection(
                            totalRevenue: totalRevenue,
                            totalFees: totalFees,
                            outstandingFees: pendingAmount,
                          ),
                          const SizedBox(height: 28),

                          // Existing revenue chart preserved.

                          // Added dynamic payment analytics. These are separate
                          // from the existing Revenue Trend chart above.
                          _buildPaymentAnalytics(
                            paymentDocs: paymentDocs,
                            paidCount: paidCount,
                            pendingCount: pendingStatusCount,
                            notPaidCount: notPaidCount,
                            overdueCount: overdueCount,
                            monthlyIncome: monthlyIncome,
                            totalFees: totalFees,
                            outstandingFees: pendingAmount,
                          ),
                          const SizedBox(height: 28),

                          // Search & Status Filters.
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: 300,
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  style: const TextStyle(color: Colors.white),
                                  onChanged: (_) {
                                    // Do not call setState here.
                                    // The controller itself is a Listenable and
                                    // ValueListenableBuilder below updates only
                                    // the payment results area.
                                  },
                                  decoration: InputDecoration(
                                    hintText: "Search student name, UID...",
                                    hintStyle: const TextStyle(
                                      color: textSecondary,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: textSecondary,
                                    ),
                                    suffixIcon: searchQuery.isEmpty
                                        ? null
                                        : IconButton(
                                            icon: const Icon(
                                              Icons.clear,
                                              color: textSecondary,
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              _searchFocusNode.requestFocus();
                                            },
                                          ),
                                    filled: true,
                                    fillColor: cardColor,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              _buildFilterDropdown(),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Each student now has a payment action menu.
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: filteredList.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(40.0),
                                    child: Center(
                                      child: Text(
                                        "No payment records found for selected period.",
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: filteredList.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(
                                          color: Colors.white12,
                                          height: 1,
                                        ),
                                    itemBuilder: (context, index) {
                                      return _buildStudentPaymentTile(
                                        filteredList[index],
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStudentPaymentTile(Map<String, dynamic> item) {
    final isActive = _isStudentActive(item);
    final name = _studentDisplayName(item);
    final studentId = _getStudentId(item);

    final course =
        (item['course'] ??
                item['courseName'] ??
                item['course_name'] ??
                item['instrument'] ??
                item['preferredInstrument'] ??
                item['preferred_instrument'] ??
                'N/A')
            .toString()
            .trim();

    final phone =
        (item['phone'] ?? item['phoneNumber'] ?? item['phone_number'] ?? 'N/A')
            .toString()
            .trim();

    final fee = item['monthlyFee'] is num
        ? (item['monthlyFee'] as num).toDouble()
        : 0.0;

    final status = (item['displayStatus'] ?? 'Not Paid').toString();

    final payment = item['payment'] as Map<String, dynamic>?;

    final statusColor = status == 'Paid'
        ? successColor
        : (status == 'Not Paid' || status == 'Overdue')
        ? errorColor
        : warningColor;

    Widget buildPaymentMenu() {
      return PopupMenuButton<String>(
        enabled: isActive,
        tooltip: isActive
            ? "Payment options"
            : "Payment controls locked for inactive student",
        icon: Icon(
          isActive ? Icons.more_vert : Icons.lock_rounded,
          color: isActive ? textSecondary : errorColor,
        ),
        color: cardColor,
        onSelected: isActive
            ? (value) {
                _handlePaymentAction(value, item);
              }
            : null,
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'edit_fee',
            child: Text(
              "Edit Monthly Fee",
              style: TextStyle(color: Colors.white),
            ),
          ),
          const PopupMenuItem(
            value: 'payment_method',
            child: Text(
              "Edit Payment Method",
              style: TextStyle(color: Colors.white),
            ),
          ),
          if (status != 'Paid')
            const PopupMenuItem(
              value: 'mark_paid',
              child: Text(
                "Mark as Paid",
                style: TextStyle(color: successColor),
              ),
            ),
          const PopupMenuItem(
            value: 'change_status',
            child: Text(
              "Edit Payment Status",
              style: TextStyle(color: warningColor),
            ),
          ),
          if (status == 'Paid')
            const PopupMenuItem(
              value: 'receipt',
              child: Text(
                "View Receipt",
                style: TextStyle(color: Colors.white),
              ),
            ),
          if (status == 'Paid')
            const PopupMenuItem(
              value: 'download_pdf',
              child: Text(
                "Download Receipt PDF",
                style: TextStyle(color: successColor),
              ),
            ),
          const PopupMenuItem(
            value: 'history',
            child: Text(
              "Payment History",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      );
    }

    Widget buildStatusBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: statusColor.withValues(alpha: 0.42)),
        ),
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }

    Widget buildDetails() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "ID: $studentId",
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            "Course: $course",
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            "Phone: $phone",
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _buildPaymentInfoChip(
                "${_getMonthName(_selectedMonth.month)} "
                "${_selectedMonth.year}",
                Icons.calendar_month_rounded,
              ),
              _buildPaymentInfoChip(
                "Monthly Fee: ₹${fee.toStringAsFixed(0)}",
                Icons.payments_rounded,
              ),
              if (payment != null &&
                  (payment['paymentMethod'] ?? '').toString().isNotEmpty)
                _buildPaymentInfoChip(
                  (payment['paymentMethod']).toString().toUpperCase(),
                  Icons.account_balance_wallet_rounded,
                ),
              if (payment != null &&
                  (payment['receiptNumber'] ?? '').toString().isNotEmpty)
                _buildPaymentInfoChip(
                  "Receipt: ${payment['receiptNumber']}",
                  Icons.receipt_long_rounded,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildAccountAccessBadge(isActive),
              if (!isActive)
                const Text(
                  'Payment controls locked',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;

        final avatar = Container(
          width: isCompact ? 48 : 54,
          height: isCompact ? 48 : 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primaryColor, secondaryColor],
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.22),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              _initials(name),
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompact ? 15 : 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );

        final nameWidget = Text(
          name,
          maxLines: isCompact ? 2 : 1,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: isCompact ? 17 : 16,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        );

        final desktopLayout = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nameWidget,
                  const SizedBox(height: 9),
                  buildDetails(),
                ],
              ),
            ),
            const SizedBox(width: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 110, maxWidth: 145),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  buildStatusBadge(),
                  const SizedBox(height: 9),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAccountAccessBadge(isActive),
                      const SizedBox(width: 2),
                      buildPaymentMenu(),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        final mobileLayout = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: nameWidget,
                  ),
                ),
                const SizedBox(width: 7),
                buildPaymentMenu(),
              ],
            ),
            const SizedBox(height: 14),
            buildDetails(),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Expanded(child: buildStatusBadge())],
            ),
          ],
        );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 20,
            vertical: isCompact ? 17 : 18,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(isCompact ? 16 : 14),
          ),
          child: isCompact ? mobileLayout : desktopLayout,
        );
      },
    );
  }

  Widget _buildPaymentInfoChip(String text, IconData icon) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: secondaryColor, size: 13),
          const SizedBox(width: 5),
          Text(
            text,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ADDED: Student account access is controlled by accountStatus.
  // Active students can use payment actions; inactive students remain visible
  // for historical/payment record visibility but their payment controls are locked.
  bool _isStudentActive(Map<String, dynamic> item) {
    final rawStatus = (item['accountStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (rawStatus.isEmpty) {
      // Backward compatible: older student documents without accountStatus
      // continue to behave as Active.
      return true;
    }

    return rawStatus == 'active';
  }

  Widget _buildAccountAccessBadge(bool isActive) {
    final color = isActive ? successColor : errorColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.lock_open_rounded : Icons.lock_rounded,
            color: color,
            size: 12,
          ),
          const SizedBox(width: 5),
          Text(
            isActive ? 'ACTIVE' : 'INACTIVE',
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  String _getStudentId(Map<String, dynamic> item) {
    final value =
        item['studentId'] ??
        item['student_id'] ??
        item['studentID'] ??
        item['student_id_number'];

    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }

    return 'Not assigned';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.isEmpty || parts.first.isEmpty) {
      return 'U';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}'
            '${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _handlePaymentAction(
    String action,
    Map<String, dynamic> item,
  ) async {
    // ADDED: never allow payment actions for an inactive student, even if an
    // action is triggered programmatically or from a stale UI state.
    if (!_isStudentActive(item)) {
      _showError(
        '${item['studentName'] ?? 'Student'} is inactive. '
        'Payment controls are locked until the account is Active.',
      );
      return;
    }

    switch (action) {
      case 'edit_fee':
        await _editMonthlyFee(item);
        break;

      case 'payment_method':
        await _editPaymentMethod(item);
        break;

      case 'mark_paid':
        await _markAsPaid(item);
        break;

      case 'change_status':
        await _showPaymentStatusChanger(item);
        break;

      case 'receipt':
        _showReceipt(item);
        break;

      case 'download_pdf':
        await _downloadReceiptPdf(item);
        break;

      case 'history':
        await _showPaymentHistory(item);
        break;
    }
  }

  Future<void> _showPaymentStatusChanger(Map<String, dynamic> item) async {
    if (!_isStudentActive(item)) {
      _showError(
        '${item['studentName'] ?? 'Student'} is inactive. '
        'Payment status cannot be changed.',
      );
      return;
    }

    final name = (item['studentName'] ?? 'Student').toString();
    final fee = item['monthlyFee'] is num
        ? (item['monthlyFee'] as num).toDouble()
        : 0.0;
    final monthLabel =
        '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}';

    final payment = item['payment'] as Map<String, dynamic>?;
    final currentStatus =
        (payment?['status'] ?? item['displayStatus'] ?? 'Not Paid')
            .toString()
            .trim();

    final currentMethod = (payment?['paymentMethod'] ?? 'upi')
        .toString()
        .toLowerCase();

    const paymentMethods = <String>[
      'upi',
      'cash',
      'bank transfer',
      'card',
      'other',
    ];

    String selectedStatus = currentStatus;
    String selectedMethod = paymentMethods.contains(currentMethod)
        ? currentMethod
        : 'upi';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final statusColor = selectedStatus == 'Paid'
                ? successColor
                : selectedStatus == 'Not Paid'
                ? errorColor
                : warningColor;

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 500,
                constraints: const BoxConstraints(maxHeight: 680),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.38),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  primaryColor.withValues(alpha: 0.25),
                                  secondaryColor.withValues(alpha: 0.12),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.payments_rounded,
                              color: secondaryColor,
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Edit Payment Status',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: primaryColor,
                              child: Text(
                                _initials(name),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$monthLabel  •  ₹${fee.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Payment Status',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _statusChoiceTile(
                        dialogContext,
                        value: 'Paid',
                        title: 'Paid',
                        subtitle: 'Payment is received for this month.',
                        icon: Icons.check_circle_rounded,
                        color: successColor,
                        isCurrent: currentStatus.toLowerCase() == 'paid',
                        isSelected: selectedStatus == 'Paid',
                        onSelect: () {
                          setDialogState(() {
                            selectedStatus = 'Paid';
                          });
                        },
                      ),
                      const SizedBox(height: 9),
                      _statusChoiceTile(
                        dialogContext,
                        value: 'Pending',
                        title: 'Pending',
                        subtitle:
                            'Payment is expected but has not been received.',
                        icon: Icons.schedule_rounded,
                        color: warningColor,
                        isCurrent: currentStatus.toLowerCase() == 'pending',
                        isSelected: selectedStatus == 'Pending',
                        onSelect: () {
                          setDialogState(() {
                            selectedStatus = 'Pending';
                          });
                        },
                      ),
                      const SizedBox(height: 9),
                      _statusChoiceTile(
                        dialogContext,
                        value: 'Not Paid',
                        title: 'Not Paid',
                        subtitle: 'Record this month as unpaid.',
                        icon: Icons.cancel_rounded,
                        color: errorColor,
                        isCurrent: currentStatus.toLowerCase() == 'not paid',
                        isSelected: selectedStatus == 'Not Paid',
                        onSelect: () {
                          setDialogState(() {
                            selectedStatus = 'Not Paid';
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Payment Method',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedOpacity(
                        opacity: selectedStatus == 'Paid' ? 1 : 0.45,
                        duration: const Duration(milliseconds: 160),
                        child: IgnorePointer(
                          ignoring: selectedStatus != 'Paid',
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedMethod,
                            dropdownColor: cardColor,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              prefixIcon: Icon(
                                Icons.account_balance_wallet_rounded,
                                color: statusColor,
                                size: 19,
                              ),
                              hintText: 'Select payment method',
                              hintStyle: const TextStyle(color: textSecondary),
                              filled: true,
                              fillColor: bgColor,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.white10,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'upi',
                                child: Text('UPI'),
                              ),
                              DropdownMenuItem(
                                value: 'cash',
                                child: Text('Cash'),
                              ),
                              DropdownMenuItem(
                                value: 'bank transfer',
                                child: Text('Bank Transfer'),
                              ),
                              DropdownMenuItem(
                                value: 'card',
                                child: Text('Card'),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() {
                                  selectedMethod = value;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        selectedStatus == 'Paid'
                            ? 'The selected method will be saved with this month\'s paid payment.'
                            : 'Payment method is disabled until the status is Paid.',
                        style: const TextStyle(
                          color: textSecondary,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          currentStatus.toLowerCase() == 'paid' &&
                                  selectedStatus != 'Paid'
                              ? 'Changing from Paid will remove the payment date, payment method, amount paid and receipt number. The transaction will disappear from Payment History.'
                              : selectedStatus == 'Paid'
                              ? 'Paid payments are included in Payment History and can have a receipt number.'
                              : 'New/unpaid students start as Not Paid. Pending is only used when the admin explicitly selects Pending. Neither Pending nor Not Paid is included in Payment History.',
                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: textSecondary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: statusColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 17,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(dialogContext, {
                                'status': selectedStatus,
                                'paymentMethod': selectedMethod,
                              });
                            },
                            icon: const Icon(Icons.save_rounded, size: 17),
                            label: const Text(
                              'Save Changes',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;

    final newStatus = result['status'] ?? currentStatus;
    final newMethod = result['paymentMethod'] ?? selectedMethod;

    final statusChanged =
        newStatus.toLowerCase() != currentStatus.toLowerCase();
    final methodChanged =
        newMethod.toLowerCase() != currentMethod.toLowerCase();

    if (!statusChanged && !methodChanged) {
      return;
    }

    await _confirmPaymentStatusChange(
      item,
      newStatus,
      selectedPaymentMethod: newMethod,
    );
  }

  Widget _statusChoiceTile(
    BuildContext dialogContext, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isCurrent,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.10) : bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.60) : Colors.white10,
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: color.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            'CURRENT',
                            style: TextStyle(
                              color: color,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : Colors.white24,
                  width: 2,
                ),
                color: isSelected ? color : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 15,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPaymentStatusChange(
    Map<String, dynamic> item,
    String newStatus, {
    required String selectedPaymentMethod,
  }) async {
    final name = (item['studentName'] ?? 'Student').toString();
    final fee = item['monthlyFee'] is num
        ? (item['monthlyFee'] as num).toDouble()
        : 0.0;
    final monthLabel =
        '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}';

    final payment = item['payment'] as Map<String, dynamic>?;
    final currentStatus =
        (payment?['status'] ?? item['displayStatus'] ?? 'Not Paid')
            .toString()
            .trim();
    final currentMethod = (payment?['paymentMethod'] ?? 'N/A').toString();

    final isPaid = newStatus == 'Paid';
    final isNotPaid = newStatus == 'Not Paid';
    final color = isPaid
        ? successColor
        : isNotPaid
        ? errorColor
        : warningColor;

    final leavingPaid = currentStatus.toLowerCase() == 'paid' && !isPaid;
    final changingPaidMethod =
        currentStatus.toLowerCase() == 'paid' &&
        isPaid &&
        currentMethod.toLowerCase() != selectedPaymentMethod.toLowerCase();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      changingPaidMethod
                          ? Icons.account_balance_wallet_rounded
                          : isPaid
                          ? Icons.check_circle_rounded
                          : isNotPaid
                          ? Icons.warning_rounded
                          : Icons.schedule_rounded,
                      color: color,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Confirm Payment Changes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$monthLabel  •  ₹${fee.toStringAsFixed(0)}',
                  style: const TextStyle(color: textSecondary),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.22)),
                  ),
                  child: Text(
                    leavingPaid
                        ? 'The payment will become $newStatus. The paid amount, payment date, payment method and receipt number will be removed, and the transaction will disappear from Payment History.'
                        : changingPaidMethod
                        ? 'The payment will remain Paid. The payment method will be changed to ${selectedPaymentMethod.toUpperCase()}.'
                        : isPaid
                        ? currentStatus.toLowerCase() == 'paid'
                              ? 'The payment will remain Paid with ${selectedPaymentMethod.toUpperCase()} as the payment method.'
                              : 'This month will be recorded as Paid using ${selectedPaymentMethod.toUpperCase()}. A receipt number will be generated.'
                        : 'This month will be recorded as $newStatus.',
                    style: const TextStyle(
                      color: textSecondary,
                      height: 1.45,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text(
                        'Confirm Changes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    await _updatePaymentStatus(
      item,
      newStatus,
      selectedPaymentMethod: selectedPaymentMethod,
    );
  }

  Future<void> _updatePaymentStatus(
    Map<String, dynamic> item,
    String newStatus, {
    required String selectedPaymentMethod,
  }) async {
    final payment = item['payment'] as Map<String, dynamic>?;

    if (payment == null) {
      if (newStatus == 'Paid') {
        await _markAsPaid(item, selectedPaymentMethod: selectedPaymentMethod);
        return;
      }
      _showError('No payment record exists for this month.');
      return;
    }

    final paymentDocId = (payment['docId'] ?? '').toString();

    if (paymentDocId.isEmpty) {
      _showError('Payment record ID is missing.');
      return;
    }

    try {
      final monthName = _getMonthName(_selectedMonth.month).toLowerCase();

      final currentStatus =
          (payment['status'] ?? item['displayStatus'] ?? 'Not Paid')
              .toString()
              .trim();

      if (newStatus == 'Paid') {
        if (currentStatus.toLowerCase() == 'paid') {
          // Editing only the payment method for an existing Paid transaction
          // does not create a new receipt.
          await FirebaseFirestore.instance
              .collection('feePayments')
              .doc(paymentDocId)
              .update({
                'status': 'Paid',
                'paymentMethod': selectedPaymentMethod,
                'updatedAt': FieldValue.serverTimestamp(),
              });

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: successColor,
              content: Text(
                'Payment method changed to ${selectedPaymentMethod.toUpperCase()}.',
              ),
            ),
          );
          return;
        }

        // Pending / Not Paid -> Paid:
        // use the selected payment method and generate a fresh receipt.
        await _markAsPaid(item, selectedPaymentMethod: selectedPaymentMethod);
        return;
      }

      // Paid -> Pending / Not Paid:
      // Keep the monthly record but remove every paid transaction field.
      await FirebaseFirestore.instance
          .collection('feePayments')
          .doc(paymentDocId)
          .update({
            'status': newStatus,
            'amountPaid': 0,
            'paymentDate': FieldValue.delete(),
            'lastPaymentDate': FieldValue.delete(),
            'paymentMethod': FieldValue.delete(),
            'receiptNumber': FieldValue.delete(),
            'statusChangedAt': FieldValue.serverTimestamp(),
            'statusChangedFrom': currentStatus,
            'updatedAt': FieldValue.serverTimestamp(),
            'paymentMonth': monthName,
            'paymentYear': _selectedMonth.year,
            'monthlyFee': item['monthlyFee'] is num
                ? item['monthlyFee']
                : payment['monthlyFee'],
            'nextDueDate': Timestamp.fromDate(
              DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1),
            ),
          });

      // Keep the student's current fee status synchronized.
      final userDocId = item['docId']?.toString();
      if (userDocId != null && userDocId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .update({
              'feeStatus': newStatus,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: newStatus == 'Not Paid' ? errorColor : warningColor,
          content: Text(
            '${item['studentName'] ?? 'Student'} is now $newStatus for $monthName ${_selectedMonth.year}. '
            'The paid receipt was removed from Payment History.',
          ),
        ),
      );
    } catch (e) {
      _showError('Unable to change payment status.');
    }
  }

  Future<void> _editMonthlyFee(Map<String, dynamic> item) async {
    if (!_isStudentActive(item)) {
      _showError(
        '${item['studentName'] ?? 'Student'} is inactive. '
        'Monthly fee editing is locked.',
      );
      return;
    }

    final value = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _EditMonthlyFeeDialog(
          initialFee: (item['monthlyFee'] ?? 0).toString(),
        );
      },
    );

    if (value == null || value < 0) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(item['docId'])
          .update({
            'monthlyFee': value,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      final payment = item['payment'] as Map<String, dynamic>?;

      if (payment != null &&
          (payment['status'] ?? '').toString().toLowerCase() != 'paid') {
        final paymentDocId = payment['docId'];

        if (paymentDocId != null) {
          await FirebaseFirestore.instance
              .collection('feePayments')
              .doc(paymentDocId)
              .update({
                'monthlyFee': value,
                'updatedAt': FieldValue.serverTimestamp(),
              });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Monthly fee updated successfully.")),
        );
      }
    } catch (e) {
      _showError("Unable to update monthly fee.");
    }
  }

  Future<void> _editPaymentMethod(Map<String, dynamic> item) async {
    if (!_isStudentActive(item)) {
      _showError(
        '${item['studentName'] ?? 'Student'} is inactive. '
        'Payment method editing is locked.',
      );
      return;
    }

    final payment = item['payment'] as Map<String, dynamic>?;

    final current = (payment?['paymentMethod'] ?? 'upi')
        .toString()
        .toLowerCase();

    String selected = current;

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: cardColor,
              title: const Text(
                "Payment Method",
                style: TextStyle(color: Colors.white),
              ),
              content: DropdownButtonFormField<String>(
                initialValue: selected,
                dropdownColor: cardColor,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primaryColor),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'upi', child: Text("UPI")),
                  DropdownMenuItem(value: 'cash', child: Text("Cash")),
                  DropdownMenuItem(
                    value: 'bank transfer',
                    child: Text("Bank Transfer"),
                  ),
                  DropdownMenuItem(value: 'card', child: Text("Card")),
                  DropdownMenuItem(value: 'other', child: Text("Other")),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selected = value);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: textSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                  ),
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text(
                    "Save",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final paymentDocId = payment?['docId'];

    if (paymentDocId == null) {
      await _markAsPaid(item, selectedPaymentMethod: result);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('feePayments')
          .doc(paymentDocId)
          .update({
            'paymentMethod': result,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Payment method updated.")),
        );
      }
    } catch (e) {
      _showError("Unable to update payment method.");
    }
  }

  Future<void> _markAsPaid(
    Map<String, dynamic> item, {
    String? selectedPaymentMethod,
  }) async {
    if (!_isStudentActive(item)) {
      _showError(
        '${item['studentName'] ?? 'Student'} is inactive. '
        'Payment cannot be recorded.',
      );
      return;
    }

    String paymentMethod = selectedPaymentMethod ?? 'upi';

    if (selectedPaymentMethod == null) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: cardColor,
            title: const Text(
              "Mark Payment as Paid",
              style: TextStyle(color: Colors.white),
            ),
            content: DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              dropdownColor: cardColor,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Payment Method",
                labelStyle: TextStyle(color: textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: primaryColor),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'upi', child: Text("UPI")),
                DropdownMenuItem(value: 'cash', child: Text("Cash")),
                DropdownMenuItem(
                  value: 'bank transfer',
                  child: Text("Bank Transfer"),
                ),
                DropdownMenuItem(value: 'card', child: Text("Card")),
                DropdownMenuItem(value: 'other', child: Text("Other")),
              ],
              onChanged: (value) {
                if (value != null) {
                  paymentMethod = value;
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: textSecondary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                onPressed: () => Navigator.pop(context, paymentMethod),
                child: const Text(
                  "Continue",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      );

      if (result == null) return;

      paymentMethod = result;
    }

    try {
      final now = DateTime.now();
      final selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month,
        1,
      );

      final studentName = (item['studentName'] ?? 'Student').toString();

      final uid = (item['uid'] ?? '').toString();

      final studentId = _getStudentId(item);

      final monthlyFee = item['monthlyFee'] is num
          ? (item['monthlyFee'] as num).toDouble()
          : 0.0;

      final receiptNumber = await _generateReceiptNumber(studentName, uid);

      final nextDueDate = DateTime(
        selectedMonth.year,
        selectedMonth.month + 1,
        1,
      );

      final payment = item['payment'] as Map<String, dynamic>?;

      final existingDocId = payment?['docId']?.toString();

      final data = <String, dynamic>{
        'uid': uid,
        'studentId': studentId,
        'studentName': studentName,
        'monthlyFee': monthlyFee,
        'amountPaid': monthlyFee,
        'status': 'Paid',
        'paymentDate': FieldValue.serverTimestamp(),
        'lastPaymentDate': FieldValue.serverTimestamp(),
        'nextDueDate': Timestamp.fromDate(nextDueDate),
        'joinDate': item['joinDate'] ?? FieldValue.serverTimestamp(),
        'paymentMethod': paymentMethod,
        'paymentMonth': _getMonthName(selectedMonth.month).toLowerCase(),
        'paymentYear': selectedMonth.year,
        'receiptNumber': receiptNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (existingDocId != null) {
        await FirebaseFirestore.instance
            .collection('feePayments')
            .doc(existingDocId)
            .update(data);
      } else {
        await FirebaseFirestore.instance.collection('feePayments').add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(item['docId'])
          .update({
            'feeStatus': 'Paid',
            'lastPaymentDate': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Payment recorded. Receipt: "
            "$receiptNumber",
          ),
        ),
      );

      _showReceipt({
        ...item,
        'monthlyFee': monthlyFee,
        'payment': {
          ...data,
          'receiptNumber': receiptNumber,
          'paymentDate': Timestamp.fromDate(now),
          'docId': existingDocId ?? '',
        },
        'displayStatus': 'Paid',
      });
    } catch (e) {
      _showError("Unable to save payment.");
    }
  }

  Future<String> _generateReceiptNumber(String studentName, String uid) async {
    final cleanName = studentName
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();

    final prefix = cleanName.length >= 4
        ? cleanName.substring(0, 4)
        : cleanName.padRight(4, 'X');

    final randomPart = DateTime.now().microsecondsSinceEpoch
        .toString()
        .substring(7);

    final candidate = '${prefix}_$randomPart';

    final existing = await FirebaseFirestore.instance
        .collection('feePayments')
        .where('receiptNumber', isEqualTo: candidate)
        .limit(1)
        .get();

    if (existing.docs.isEmpty) {
      return candidate;
    }

    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _showReceipt(Map<String, dynamic> item) {
    final payment = item['payment'] as Map<String, dynamic>?;

    if (payment == null) {
      _showError("No paid receipt is available for this month.");
      return;
    }

    final name = (item['studentName'] ?? 'Student').toString();

    final studentId = _getStudentId(item);

    final course =
        (item['course'] ??
                item['courseName'] ??
                item['course_name'] ??
                item['instrument'] ??
                item['preferredInstrument'] ??
                item['preferred_instrument'] ??
                'N/A')
            .toString()
            .trim();

    final fee = payment['amountPaid'] is num
        ? (payment['amountPaid'] as num).toDouble()
        : item['monthlyFee'] is num
        ? (item['monthlyFee'] as num).toDouble()
        : 0.0;

    final receiptNumber = (payment['receiptNumber'] ?? 'N/A').toString();

    final method = (payment['paymentMethod'] ?? 'N/A').toString();

    final paymentDate =
        _timestampToDate(payment['paymentDate']) ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.music_note, color: primaryColor, size: 42),
                const SizedBox(height: 8),
                const Text(
                  academyName,
                  style: TextStyle(
                    color: Color(0xFF171C35),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "OFFICIAL PAYMENT RECEIPT",
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(height: 28),
                _receiptRow("Receipt No.", receiptNumber),
                _receiptRow("Student", name),
                _receiptRow("Student ID", studentId),
                _receiptRow("Course", course),
                _receiptRow(
                  "Payment Month",
                  "${(payment['paymentMonth'] ?? _getMonthName(_selectedMonth.month)).toString()} "
                      "${(payment['paymentYear'] ?? _selectedMonth.year).toString()}",
                ),
                _receiptRow(
                  "Payment Date",
                  "${paymentDate.day.toString().padLeft(2, '0')}/"
                      "${paymentDate.month.toString().padLeft(2, '0')}/"
                      "${paymentDate.year}",
                ),
                _receiptRow("Payment Method", method.toUpperCase()),
                const Divider(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Amount Paid",
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "₹${fee.toStringAsFixed(0)}",
                      style: const TextStyle(
                        color: primaryColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  "Payment Status: PAID",
                  style: TextStyle(
                    color: successColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "This receipt is generated by the academy payment system.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 11),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: const BorderSide(color: primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          await _downloadReceiptPdf(item);
                        },
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text("Download PDF"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Close",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadReceiptPdf(Map<String, dynamic> item) async {
    final payment = item['payment'] as Map<String, dynamic>?;

    if (payment == null ||
        (payment['status'] ?? '').toString().toLowerCase() != 'paid') {
      _showError("No paid receipt is available for this month.");
      return;
    }

    try {
      final name = (item['studentName'] ?? 'Student').toString();
      final studentId = _getStudentId(item);
      final course = (item['course'] ?? 'N/A').toString();

      final fee = payment['amountPaid'] is num
          ? (payment['amountPaid'] as num).toDouble()
          : item['monthlyFee'] is num
          ? (item['monthlyFee'] as num).toDouble()
          : 0.0;

      final receiptNumber = (payment['receiptNumber'] ?? 'N/A').toString();

      final method = (payment['paymentMethod'] ?? 'N/A').toString();

      final paymentDate =
          _timestampToDate(payment['paymentDate']) ?? DateTime.now();

      final paymentMonth = (payment['paymentMonth'] ?? '').toString().trim();

      final paymentYear = (payment['paymentYear'] ?? _selectedMonth.year)
          .toString();

      final document = pw.Document();

      document.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(40),
          build: (context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(28),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  width: 1.5,
                  color: const pdf.PdfColor.fromInt(0xFF7C4DFF),
                ),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          '♫',
                          style: const pw.TextStyle(
                            fontSize: 30,
                            color: pdf.PdfColor.fromInt(0xFF7C4DFF),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          academyName,
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: const pdf.PdfColor.fromInt(0xFF171C35),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'OFFICIAL PAYMENT RECEIPT',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: const pdf.PdfColor.fromInt(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 18),
                  pw.Divider(),
                  pw.SizedBox(height: 12),
                  _pdfReceiptRow('Receipt No.', receiptNumber),
                  _pdfReceiptRow('Student', name),
                  _pdfReceiptRow('Student ID', studentId),
                  _pdfReceiptRow('Course', course),
                  _pdfReceiptRow(
                    'Payment Month',
                    paymentMonth.isEmpty
                        ? '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}'
                        : '$paymentMonth $paymentYear',
                  ),
                  _pdfReceiptRow(
                    'Payment Date',
                    '${paymentDate.day.toString().padLeft(2, '0')}/'
                        '${paymentDate.month.toString().padLeft(2, '0')}/'
                        '${paymentDate.year}',
                  ),
                  _pdfReceiptRow('Payment Method', method.toUpperCase()),
                  pw.SizedBox(height: 12),
                  pw.Divider(),
                  pw.SizedBox(height: 14),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Amount Paid',
                        style: pw.TextStyle(
                          fontSize: 17,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'INR ${fee.toStringAsFixed(0)}',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: const pdf.PdfColor.fromInt(0xFF7C4DFF),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Center(
                    child: pw.Text(
                      'PAYMENT STATUS: PAID',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: const pdf.PdfColor.fromInt(0xFF00A85A),
                      ),
                    ),
                  ),
                  pw.Spacer(),
                  pw.Divider(),
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.Text(
                      'This receipt is generated by the academy payment system.',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: pdf.PdfColor.fromInt(0xFF777777),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      final bytes = await document.save();

      final safeName = name
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');

      final safeReceipt = receiptNumber.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );

      await Printing.sharePdf(
        bytes: bytes,
        filename: '${safeName}_Receipt_$safeReceipt.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Receipt PDF generated successfully.")),
        );
      }
    } catch (e) {
      _showError("Unable to generate the receipt PDF.");
    }
  }

  pw.Widget _pdfReceiptRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 10,
                color: pdf.PdfColor.fromInt(0xFF666666),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: const pdf.PdfColor.fromInt(0xFF222222),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPaymentHistory(Map<String, dynamic> item) async {
    final uid = (item['uid'] ?? '').toString();
    final name = (item['studentName'] ?? 'Student').toString();

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('feePayments')
          .where('uid', isEqualTo: uid)
          .get();

      final records = snapshot.docs
          .map((doc) {
            return {...doc.data(), 'docId': doc.id};
          })
          .where((record) {
            // Payment History contains actual paid transactions only.
            return (record['status'] ?? '').toString().toLowerCase() == 'paid';
          })
          .toList();

      records.sort((a, b) {
        final aDate =
            _timestampToDate(a['paymentDate']) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final bDate =
            _timestampToDate(b['paymentDate']) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bDate.compareTo(aDate);
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 620,
              constraints: const BoxConstraints(maxHeight: 560),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryColor.withValues(alpha: 0.32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: successColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          color: successColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Payment History',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              name,
                              style: const TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: secondaryColor,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Only completed Paid transactions are shown here. '
                            'If a payment is changed to Pending or Not Paid, '
                            'its paid history entry disappears automatically.',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: records.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 55),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  color: textSecondary,
                                  size: 44,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'No paid payment history',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'Paid transactions will appear here.',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: records.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final record = records[index];

                              final amount = record['amountPaid'] is num
                                  ? (record['amountPaid'] as num).toDouble()
                                  : 0.0;

                              final month = (record['paymentMonth'] ?? '')
                                  .toString();
                              final year = (record['paymentYear'] ?? '')
                                  .toString();
                              final method = (record['paymentMethod'] ?? 'N/A')
                                  .toString()
                                  .toUpperCase();
                              final receipt = (record['receiptNumber'] ?? 'N/A')
                                  .toString();

                              final paymentDate = _timestampToDate(
                                record['paymentDate'],
                              );
                              final dateLabel = paymentDate == null
                                  ? 'Date not available'
                                  : '${paymentDate.day.toString().padLeft(2, '0')}/'
                                        '${paymentDate.month.toString().padLeft(2, '0')}/'
                                        '${paymentDate.year}';

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: successColor.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: successColor.withValues(
                                          alpha: 0.11,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: successColor,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$month $year',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$method  •  $dateLabel',
                                            style: const TextStyle(
                                              color: textSecondary,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Receipt: $receipt',
                                            style: const TextStyle(
                                              color: textSecondary,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '₹${amount.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: successColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      _showError("Unable to load payment history.");
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: errorColor),
    );
  }

  void _scheduleCurrentMonthPaymentSync(
    List<QueryDocumentSnapshot> students,
    List<QueryDocumentSnapshot> paymentDocs,
  ) {
    final now = DateTime.now();
    final isCurrentMonth =
        _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    // Only create records for the real current month. Selecting an old month
    // should never silently create historical payment documents.
    if (!isCurrentMonth || _isSyncingCurrentMonthPayments || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isSyncingCurrentMonthPayments) return;
      _ensureCurrentMonthPaymentRecords(students, paymentDocs);
    });
  }

  Future<void> _ensureCurrentMonthPaymentRecords(
    List<QueryDocumentSnapshot> students,
    List<QueryDocumentSnapshot> paymentDocs,
  ) async {
    if (_isSyncingCurrentMonthPayments || !mounted) return;

    final now = DateTime.now();
    final monthName = _getMonthName(now.month).toLowerCase();

    _isSyncingCurrentMonthPayments = true;

    try {
      final existingKeys = <String>{};

      for (final doc in paymentDocs) {
        final data = doc.data() as Map<String, dynamic>;

        final paymentMonth = (data['paymentMonth'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final paymentYear = int.tryParse(
          (data['paymentYear'] ?? '').toString(),
        );

        if (paymentMonth != monthName || paymentYear != now.year) {
          continue;
        }

        final uid = (data['uid'] ?? '').toString().trim();
        final studentId = (data['studentId'] ?? '').toString().trim();

        if (uid.isNotEmpty) {
          existingKeys.add('uid:$uid');
        }
        if (studentId.isNotEmpty) {
          existingKeys.add('student:$studentId');
        }
      }

      for (final studentDoc in students) {
        final student = studentDoc.data() as Map<String, dynamic>;

        final uid = (student['uid'] ?? studentDoc.id).toString().trim();
        final studentId = _getStudentId(student);

        final hasUidRecord =
            uid.isNotEmpty && existingKeys.contains('uid:$uid');
        final hasStudentIdRecord =
            studentId != 'Not assigned' &&
            existingKeys.contains('student:$studentId');

        if (hasUidRecord || hasStudentIdRecord) {
          continue;
        }

        final monthlyFee = student['monthlyFee'] is num
            ? (student['monthlyFee'] as num).toDouble()
            : 0.0;

        final studentName = _studentDisplayName(student);
        final safeKey = _safePaymentDocumentKey(
          uid.isNotEmpty ? uid : studentId,
        );

        if (safeKey.isEmpty) continue;

        // Deterministic ID prevents duplicate current-month records if the
        // dashboard is opened from more than one browser/device.
        final paymentDocId =
            '${safeKey}_${now.year}_${now.month.toString().padLeft(2, '0')}';

        final paymentRef = FirebaseFirestore.instance
            .collection('feePayments')
            .doc(paymentDocId);

        final existing = await paymentRef.get();

        if (existing.exists) {
          existingKeys.add('uid:$uid');
          if (studentId != 'Not assigned') {
            existingKeys.add('student:$studentId');
          }
          continue;
        }

        final nextDueDate = DateTime(now.year, now.month + 1, 1);

        await paymentRef.set({
          'uid': uid,
          'studentId': studentId == 'Not assigned' ? '' : studentId,
          'studentName': studentName,

          'course':
              student['course'] ??
              student['courseName'] ??
              student['course_name'] ??
              student['preferredInstrument'] ??
              student['preferred_instrument'] ??
              '',

          'phone':
              student['phone'] ??
              student['phoneNumber'] ??
              student['phone_number'] ??
              '',

          'monthlyFee': monthlyFee,
          'amountPaid': 0,
          'status': 'Not Paid',
          'paymentMonth': monthName,
          'paymentYear': now.year,
          'nextDueDate': Timestamp.fromDate(nextDueDate),
          'joinDate': student['joinDate'] ?? FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'statusChangedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: false));

        existingKeys.add('uid:$uid');
        if (studentId != 'Not assigned') {
          existingKeys.add('student:$studentId');
        }
      }
    } catch (_) {
      // The live fee stream remains usable even if record creation fails.
      // The next refresh/stream rebuild will retry the missing records.
    } finally {
      _isSyncingCurrentMonthPayments = false;
    }
  }

  String _studentDisplayName(Map<String, dynamic> student) {
    // 1. Direct full-name fields
    final directName =
        (student['studentName'] ??
                student['student_name'] ??
                student['full_name'] ??
                student['fullName'] ??
                '')
            .toString()
            .trim();

    if (directName.isNotEmpty) {
      return directName;
    }

    // 2. First + last name
    final firstName = (student['firstName'] ?? student['first_name'] ?? '')
        .toString()
        .trim();

    final lastName = (student['lastName'] ?? student['last_name'] ?? '')
        .toString()
        .trim();

    final fullName = '$firstName $lastName'.trim();

    return fullName.isEmpty ? 'Unknown Student' : fullName;
  }

  String _safePaymentDocumentKey(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  Widget _buildPaymentAnalytics({
    required List<QueryDocumentSnapshot> paymentDocs,
    required int paidCount,
    required int pendingCount,
    required int notPaidCount,
    required int overdueCount,
    required double monthlyIncome,
    required double totalFees,
    required double outstandingFees,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumns = width > 1050;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Live collection status for ${_getMonthName(_selectedMonth.month)} '
              '${_selectedMonth.year}.',
              style: const TextStyle(color: textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            if (twoColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildPaymentStatusGraph(
                      paidCount: paidCount,
                      pendingCount: pendingCount,
                      notPaidCount: notPaidCount,
                      overdueCount: overdueCount,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildFeeCollectionGraph(
                      monthlyIncome: monthlyIncome,
                      totalFees: totalFees,
                      outstandingFees: outstandingFees,
                    ),
                  ),
                ],
              )
            else ...[
              _buildPaymentStatusGraph(
                paidCount: paidCount,
                pendingCount: pendingCount,
                notPaidCount: notPaidCount,
                overdueCount: overdueCount,
              ),
              const SizedBox(height: 16),
              _buildFeeCollectionGraph(
                monthlyIncome: monthlyIncome,
                totalFees: totalFees,
                outstandingFees: outstandingFees,
              ),
            ],
            const SizedBox(height: 16),
            _buildYearlyRevenueGraph(paymentDocs),
          ],
        );
      },
    );
  }

  Widget _buildAnalyticsCard({
    required String title,
    required String subtitle,
    required Widget child,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.055),
            blurRadius: 22,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildPaymentStatusGraph({
    required int paidCount,
    required int pendingCount,
    required int notPaidCount,
    required int overdueCount,
  }) {
    final total = paidCount + pendingCount + notPaidCount + overdueCount;

    return _buildAnalyticsCard(
      title: 'Payment Status',
      subtitle: '$total students • current month',
      icon: Icons.donut_small_rounded,
      accent: primaryColor,
      child: SizedBox(
        height: 245,
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      centerSpaceRadius: 52,
                      sectionsSpace: 3,
                      startDegreeOffset: -90,
                      sections: [
                        _paymentPieSection(paidCount.toDouble(), successColor),
                        _paymentPieSection(
                          pendingCount.toDouble(),
                          warningColor,
                        ),
                        _paymentPieSection(notPaidCount.toDouble(), errorColor),
                        if (overdueCount > 0)
                          _paymentPieSection(
                            overdueCount.toDouble(),
                            secondaryColor,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$paidCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Paid',
                        style: TextStyle(color: textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statusLegendRow('Paid', paidCount, successColor),
                  const SizedBox(height: 11),
                  _statusLegendRow('Pending', pendingCount, warningColor),
                  const SizedBox(height: 11),
                  _statusLegendRow('Not Paid', notPaidCount, errorColor),
                  if (overdueCount > 0) ...[
                    const SizedBox(height: 11),
                    _statusLegendRow('Overdue', overdueCount, secondaryColor),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PieChartSectionData _paymentPieSection(double value, Color color) {
    return PieChartSectionData(
      value: value <= 0 ? 0.0001 : value,
      color: color,
      radius: 29,
      showTitle: false,
    );
  }

  Widget _statusLegendRow(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildFeeCollectionGraph({
    required double monthlyIncome,
    required double totalFees,
    required double outstandingFees,
  }) {
    final maxValue = [
      monthlyIncome,
      totalFees,
      outstandingFees,
    ].reduce((a, b) => a > b ? a : b);
    final chartMax = maxValue <= 0 ? 1000.0 : maxValue * 1.25;

    return _buildAnalyticsCard(
      title: 'Fee Collection',
      subtitle: 'Collected vs expected vs outstanding',
      icon: Icons.account_balance_rounded,
      accent: successColor,
      child: SizedBox(
        height: 245,
        child: BarChart(
          BarChartData(
            maxY: chartMax,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: chartMax / 4,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: Colors.white10, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  getTitlesWidget: (value, meta) {
                    const labels = ['Collected', 'Total Fees', 'Outstanding'];
                    final index = value.toInt();

                    if (index < 0 || index >= labels.length) {
                      return const SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        labels[index],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              _feeBarGroup(0, monthlyIncome, successColor),
              _feeBarGroup(1, totalFees, primaryColor),
              _feeBarGroup(2, outstandingFees, warningColor),
            ],
          ),
        ),
      ),
    );
  }

  BarChartGroupData _feeBarGroup(int x, double value, Color color) {
    return BarChartGroupData(
      x: x,
      barsSpace: 0,
      barRods: [
        BarChartRodData(
          toY: value,
          width: 34,
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: value <= 0 ? 1 : value,
            color: Colors.white.withValues(alpha: 0.025),
          ),
        ),
      ],
    );
  }

  Widget _buildYearlyRevenueGraph(List<QueryDocumentSnapshot> paymentDocs) {
    final year = _selectedMonth.year;
    final monthlyRevenue = List<double>.filled(12, 0);

    for (final doc in paymentDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().trim().toLowerCase();

      if (status != 'paid') continue;

      final paymentYear = int.tryParse((data['paymentYear'] ?? '').toString());

      if (paymentYear != year) continue;

      int? monthNumber;
      final paymentMonth = (data['paymentMonth'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (paymentMonth.isNotEmpty) {
        const monthNames = [
          'january',
          'february',
          'march',
          'april',
          'may',
          'june',
          'july',
          'august',
          'september',
          'october',
          'november',
          'december',
        ];

        final index = monthNames.indexOf(paymentMonth);
        if (index >= 0) {
          monthNumber = index + 1;
        }
      }

      monthNumber ??= _timestampToDate(data['paymentDate'])?.month;

      if (monthNumber == null || monthNumber < 1 || monthNumber > 12) {
        continue;
      }

      final amount = data['amountPaid'] is num
          ? (data['amountPaid'] as num).toDouble()
          : data['monthlyFee'] is num
          ? (data['monthlyFee'] as num).toDouble()
          : 0.0;

      monthlyRevenue[monthNumber - 1] += amount;
    }

    var maxRevenue = 0.0;
    for (final value in monthlyRevenue) {
      if (value > maxRevenue) maxRevenue = value;
    }

    final maxY = maxRevenue <= 0 ? 1000.0 : maxRevenue * 1.25;

    const monthLabels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return _buildAnalyticsCard(
      title: 'Yearly Revenue',
      subtitle: 'Actual Paid revenue • $year',
      icon: Icons.show_chart_rounded,
      accent: secondaryColor,
      child: SizedBox(
        height: 255,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: Colors.white10, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt() - 1;

                    if (index < 0 || index >= monthLabels.length) {
                      return const SizedBox.shrink();
                    }

                    return Text(
                      monthLabels[index],
                      style: const TextStyle(
                        color: textSecondary,
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(
                  12,
                  (index) => FlSpot(index + 1.0, monthlyRevenue[index]),
                ),
                isCurved: true,
                color: secondaryColor,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 3.5,
                      color: secondaryColor,
                      strokeWidth: 1.5,
                      strokeColor: cardColor,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: secondaryColor.withValues(alpha: 0.10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialSummarySection({
    required double totalRevenue,
    required double totalFees,
    required double outstandingFees,
  }) {
    final monthLabel =
        '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 1100 ? 3 : (width > 650 ? 2 : 1);

        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: width > 1200
              ? 2.5
              : width > 800
              ? 2.0
              : width > 500
              ? 1.65
              : 1.55,
          children: [
            _buildFinancialCard(
              title: 'Total Revenue',
              value: '₹${totalRevenue.toStringAsFixed(0)}',
              subtitle: 'All paid transactions',
              icon: Icons.auto_graph_rounded,
              color: primaryColor,
              accent: secondaryColor,
            ),
            _buildFinancialCard(
              title: 'Total Fees',
              value: '₹${totalFees.toStringAsFixed(0)}',
              subtitle: 'Expected • $monthLabel',
              icon: Icons.account_balance_wallet_rounded,
              color: secondaryColor,
              accent: primaryColor,
            ),
            _buildFinancialCard(
              title: 'Outstanding Fees',
              value: '₹${outstandingFees.toStringAsFixed(0)}',
              subtitle: 'Pending + Not Paid + Overdue',
              icon: Icons.pending_actions_rounded,
              color: warningColor,
              accent: errorColor,
            ),
          ],
        );
      },
    );
  }

  Widget _buildFinancialCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.42), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -22,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accent.withValues(alpha: 0.13), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: color.withValues(alpha: 0.22)),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    String title,
    String value,
    String subtitle,
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
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedStatusFilter,
          dropdownColor: cardColor,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          icon: const Icon(Icons.arrow_drop_down, color: textSecondary),
          items: ['All', 'Paid', 'Not Paid', 'Pending', 'Overdue']
              .map(
                (status) => DropdownMenuItem(
                  value: status,
                  child: Text("Status: $status"),
                ),
              )
              .toList(),
          onChanged: (val) {
            setState(() => _selectedStatusFilter = val ?? 'All');
          },
        ),
      ),
    );
  }
}

class _EditMonthlyFeeDialog extends StatefulWidget {
  const _EditMonthlyFeeDialog({required this.initialFee});

  final String initialFee;

  @override
  State<_EditMonthlyFeeDialog> createState() => _EditMonthlyFeeDialogState();
}

class _EditMonthlyFeeDialogState extends State<_EditMonthlyFeeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialFee);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    final parsed = double.tryParse(text);

    if (parsed == null || parsed < 0) {
      return;
    }

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _PaymentDashboardScreenState.cardColor,
      title: const Text(
        "Edit Monthly Fee",
        style: TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixText: "₹ ",
          prefixStyle: const TextStyle(
            color: _PaymentDashboardScreenState.textSecondary,
          ),
          hintText: "Monthly fee",
          hintStyle: const TextStyle(
            color: _PaymentDashboardScreenState.textSecondary,
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(
              color: _PaymentDashboardScreenState.primaryColor.withValues(
                alpha: 0.4,
              ),
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: _PaymentDashboardScreenState.primaryColor,
            ),
          ),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          child: const Text(
            "Cancel",
            style: TextStyle(color: _PaymentDashboardScreenState.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _PaymentDashboardScreenState.primaryColor,
          ),
          onPressed: _save,
          child: const Text("Save", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
