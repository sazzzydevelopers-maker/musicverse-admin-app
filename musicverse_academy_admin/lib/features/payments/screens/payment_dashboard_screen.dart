import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

class PaymentDashboardScreen extends StatefulWidget {
  const PaymentDashboardScreen({super.key});

  @override
  State<PaymentDashboardScreen> createState() => _PaymentDashboardScreenState();
}

class _PaymentDashboardScreenState extends State<PaymentDashboardScreen> {
  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';

  // Theme Constants matching MusicVerse Academy
  static const Color bgColor = Color(0xFF0D1020);
  static const Color cardColor = Color(0xFF171C35);
  static const Color primaryColor = Color(0xFF7C4DFF);
  static const Color secondaryColor = Color(0xFF9D6BFF);
  static const Color successColor = Color(0xFF00E676);
  static const Color errorColor = Color(0xFFFF5252);
  static const Color textSecondary = Color(0xFFB0B5D3);

  @override
  void dispose() {
    _searchController.dispose();
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
        stream: FirebaseFirestore.instance
            .collection('feePayments')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                "Unable to load payment records.",
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // Filter payments for the selected month & year
          double monthlyIncome = 0;
          int paidCount = 0;
          int pendingCount = 0;
          double pendingAmount = 0;
          int totalStudentsWithPayments = docs.length;

          List<Map<String, dynamic>> filteredList = [];

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final studentName = (data['studentName'] ?? '').toString();
            final uid = (data['uid'] ?? '').toString();
            final status = (data['status'] ?? 'Pending').toString();
            final monthlyFee = (data['monthlyFee'] is num)
                ? (data['monthlyFee'] as num).toDouble()
                : 0.0;

            // Parse payment date safely
            DateTime? pDate;
            var rawDate = data['paymentDate'];
            if (rawDate is Timestamp) {
              pDate = rawDate.toDate();
            } else if (rawDate is String) {
              pDate = DateTime.tryParse(rawDate);
            }

            bool isCurrentMonth =
                pDate != null &&
                pDate.year == _selectedMonth.year &&
                pDate.month == _selectedMonth.month;

            if (isCurrentMonth && status.toLowerCase() == 'paid') {
              monthlyIncome += monthlyFee;
              paidCount++;
            } else if (status.toLowerCase() != 'paid') {
              pendingCount++;
              pendingAmount += monthlyFee;
            }

            // Search and status filter match
            bool matchesSearch =
                _searchQuery.isEmpty ||
                studentName.toLowerCase().contains(_searchQuery) ||
                uid.toLowerCase().contains(_searchQuery);

            bool matchesStatus =
                _selectedStatusFilter == 'All' ||
                status.toLowerCase() == _selectedStatusFilter.toLowerCase();

            if (matchesSearch && matchesStatus) {
              filteredList.add({...data, 'docId': doc.id});
            }
          }

          double collectionRate = totalStudentsWithPayments > 0
              ? (paidCount / totalStudentsWithPayments) * 100
              : 0.0;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: SingleChildScrollView(
              key: ValueKey(_selectedMonth),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Subtitle & Month Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Track academy revenue, payments and outstanding fees.",
                        style: TextStyle(color: textSecondary, fontSize: 14),
                      ),
                      _buildMonthSelector(),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Summary KPI Cards
                  GridView.count(
                    crossAxisCount: MediaQuery.of(context).size.width > 1200
                        ? 4
                        : (MediaQuery.of(context).size.width > 700 ? 2 : 1),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.2,
                    children: [
                      _buildKpiCard(
                        "Monthly Income",
                        "₹${monthlyIncome.toStringAsFixed(0)}",
                        "${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}",
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
                  const SizedBox(height: 28),

                  // Revenue Trend Chart Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Revenue Trend",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Monthly income performance overview",
                          style: TextStyle(color: textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 220,
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
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
                                    getTitlesWidget: (val, meta) {
                                      const months = [
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
                                      int index = val.toInt() - 1;
                                      if (index >= 0 && index < months.length) {
                                        return Text(
                                          months[index],
                                          style: const TextStyle(
                                            color: textSecondary,
                                            fontSize: 11,
                                          ),
                                        );
                                      }
                                      return const Text('');
                                    },
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: [
                                    const FlSpot(1, 25000),
                                    const FlSpot(2, 32000),
                                    const FlSpot(3, 38000),
                                    const FlSpot(4, 41000),
                                    const FlSpot(5, 35000),
                                    const FlSpot(6, 44000),
                                    const FlSpot(7, 48000),
                                    FlSpot(
                                      _selectedMonth.month.toDouble(),
                                      monthlyIncome > 0 ? monthlyIncome : 52000,
                                    ),
                                  ],
                                  isCurved: true,
                                  color: primaryColor,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: primaryColor.withValues(alpha: 0.15),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Search & Status Filters
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          onChanged: (val) => setState(
                            () => _searchQuery = val.trim().toLowerCase(),
                          ),
                          decoration: InputDecoration(
                            hintText: "Search student name, UID...",
                            hintStyle: const TextStyle(color: textSecondary),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: textSecondary,
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

                  // Recent Payments / Filtered List Table
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
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredList.length,
                            separatorBuilder: (context, index) =>
                                const Divider(color: Colors.white12, height: 1),
                            itemBuilder: (context, index) {
                              final item = filteredList[index];
                              final name =
                                  item['studentName'] ?? 'Unknown Student';
                              final amount = item['monthlyFee'] ?? 0;
                              final status = item['status'] ?? 'Pending';
                              final pDateStr =
                                  item['paymentDate']?.toString() ?? 'N/A';

                              Color statusColor = status.toLowerCase() == 'paid'
                                  ? successColor
                                  : errorColor;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: const CircleAvatar(
                                  backgroundColor: primaryColor,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Date: $pDateStr • Status: $status",
                                  style: const TextStyle(
                                    color: textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: Text(
                                  "₹$amount",
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
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
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DateTime>(
          value: _selectedMonth,
          dropdownColor: cardColor,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          icon: const Icon(Icons.arrow_drop_down, color: textSecondary),
          items:
              [
                    DateTime(2026, 6, 1),
                    DateTime(2026, 7, 1),
                    DateTime(2026, 8, 1),
                    DateTime(2026, 9, 1),
                  ]
                  .map(
                    (date) => DropdownMenuItem(
                      value: date,
                      child: Text("${_getMonthName(date.month)} ${date.year}"),
                    ),
                  )
                  .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedMonth = val);
          },
        ),
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
          items: ['All', 'Paid', 'Pending', 'Overdue']
              .map(
                (status) => DropdownMenuItem(
                  value: status,
                  child: Text("Status: $status"),
                ),
              )
              .toList(),
          onChanged: (val) =>
              setState(() => _selectedStatusFilter = val ?? 'All'),
        ),
      ),
    );
  }
}
