import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = LocalDatabase();
  await db.database;
  runApp(NoBanSocialApp(db: db));
}

const Color brand = Color(0xFF8054E8);
const Color pale = Color(0xFFF6F2FF);

String money(int value) {
  final s = value.abs().toString();
  final out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    out.write(s[i]);
    final remaining = s.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) out.write('.');
  }
  return '${value < 0 ? '-' : ''}${out.toString()}đ';
}

String dateLabel(String? iso) {
  if (iso == null || iso.isEmpty) return 'Chưa đặt hạn';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class LocalDatabase {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final base = await getDatabasesPath();
    _database = await openDatabase(
      p.join(base, 'no_ban_social_local.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE debts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person TEXT NOT NULL,
            note TEXT NOT NULL,
            amount INTEGER NOT NULL,
            paid INTEGER NOT NULL DEFAULT 0,
            direction TEXT NOT NULL,
            dueDate TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            debtId INTEGER NOT NULL,
            amount INTEGER NOT NULL,
            note TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY(debtId) REFERENCES debts(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE posts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            author TEXT NOT NULL,
            body TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<List<Map<String, Object?>>> debts() async {
    final db = await database;
    return db.query('debts', orderBy: 'id DESC');
  }

  Future<int> addDebt({
    required String person,
    required String note,
    required int amount,
    required String direction,
    String? dueDate,
  }) async {
    final db = await database;
    return db.insert('debts', {
      'person': person.trim(),
      'note': note.trim(),
      'amount': amount,
      'paid': 0,
      'direction': direction,
      'dueDate': dueDate,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> addPayment(int debtId, int amount, String note) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('debts', where: 'id = ?', whereArgs: [debtId], limit: 1);
      if (rows.isEmpty) throw Exception('Không tìm thấy khoản nợ.');
      final debt = rows.first;
      final total = debt['amount'] as int;
      final paid = debt['paid'] as int;
      if (amount <= 0) throw Exception('Số tiền phải lớn hơn 0.');
      if (amount > total - paid) throw Exception('Số tiền trả vượt quá số dư còn lại.');
      await txn.insert('payments', {
        'debtId': debtId,
        'amount': amount,
        'note': note.trim().isEmpty ? 'Thanh toán' : note.trim(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      await txn.update('debts', {'paid': paid + amount}, where: 'id = ?', whereArgs: [debtId]);
    });
  }

  Future<List<Map<String, Object?>>> payments(int debtId) async {
    final db = await database;
    return db.query('payments', where: 'debtId = ?', whereArgs: [debtId], orderBy: 'id DESC');
  }

  Future<void> deleteDebt(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments', where: 'debtId = ?', whereArgs: [id]);
      await txn.delete('debts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> posts() async {
    final db = await database;
    return db.query('posts', orderBy: 'id DESC');
  }

  Future<void> addPost(String body) async {
    final db = await database;
    await db.insert('posts', {
      'author': 'Duy',
      'body': body.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
  }
}

class NoBanSocialApp extends StatelessWidget {
  final LocalDatabase db;
  const NoBanSocialApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nợ Bạn Social',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        scaffoldBackgroundColor: pale,
        appBarTheme: const AppBarTheme(backgroundColor: pale, elevation: 0),
      ),
      home: MainShell(db: db),
    );
  }
}

class MainShell extends StatefulWidget {
  final LocalDatabase db;
  const MainShell({super.key, required this.db});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  void refresh() => setState(() {});
  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(db: widget.db, onChanged: refresh),
      DebtPage(db: widget.db, onChanged: refresh),
      FeedPage(db: widget.db),
      const PremiumPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.favorite, color: brand),
          SizedBox(width: 8),
          Text('Nợ Bạn Social', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Tổng quan'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Khoản nợ'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Bảng tin'),
          NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium), label: 'Premium'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  final LocalDatabase db;
  final VoidCallback onChanged;
  const DashboardPage({super.key, required this.db, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: db.debts(),
      builder: (context, snap) {
        final rows = snap.data ?? [];
        int receivable = 0, payable = 0, countOpen = 0;
        for (final r in rows) {
          final rest = (r['amount'] as int) - (r['paid'] as int);
          if (rest > 0) {
            countOpen++;
            if (r['direction'] == 'Cho vay') receivable += rest;
            else payable += rest;
          }
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF7044D7), Color(0xFFB69AF7)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Xin chào Duy 👋', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
              SizedBox(height: 5),
              Text('Theo dõi các khoản vay và tiền đã trả ngay trên điện thoại.', style: TextStyle(color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _SummaryCard(title: 'Cần thu về', amount: money(receivable), icon: Icons.south_west, color: const Color(0xFF16865B))),
            const SizedBox(width: 10),
            Expanded(child: _SummaryCard(title: 'Cần trả', amount: money(payable), icon: Icons.north_east, color: const Color(0xFFD06A39))),
          ]),
          const SizedBox(height: 10),
          Card(child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFEDE7FF), child: Icon(Icons.receipt_long, color: brand)),
            title: const Text('Khoản đang theo dõi', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text('$countOpen', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: brand)),
          )),
          const SizedBox(height: 14),
          const Text('Bắt đầu nhanh', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(child: ListTile(
            leading: const Icon(Icons.add_circle, color: brand, size: 30),
            title: const Text('Ghi một khoản vay mới'),
            subtitle: const Text('Lưu trực tiếp trên thiết bị này'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => AddDebtPage(db: db)));
              onChanged();
            },
          )),
          const SizedBox(height: 10),
          Card(child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.phone_android, color: brand),
              SizedBox(width: 12),
              Expanded(child: Text('Chế độ lưu cục bộ: dữ liệu nằm trong bộ nhớ riêng của ứng dụng trên điện thoại này. Hiện chưa đồng bộ với máy khác.')),
            ]),
          )),
        ]);
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title, amount;
  final IconData icon;
  final Color color;
  const _SummaryCard({required this.title, required this.amount, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(15),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color),
      const SizedBox(height: 10),
      Text(title, style: const TextStyle(color: Colors.black54)),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(amount, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: color))),
    ]),
  ));
}

class DebtPage extends StatefulWidget {
  final LocalDatabase db;
  final VoidCallback onChanged;
  const DebtPage({super.key, required this.db, required this.onChanged});
  @override
  State<DebtPage> createState() => _DebtPageState();
}

class _DebtPageState extends State<DebtPage> {
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() { super.initState(); reload(); }
  void reload() => future = widget.db.debts();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: pale,
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final rows = snap.data ?? [];
        if (rows.isEmpty) return const Center(child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.receipt_long, size: 58, color: brand),
            SizedBox(height: 12),
            Text('Chưa có khoản vay nào', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Nhấn nút + để thêm khoản đầu tiên.'),
          ]),
        ));
        return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 90), children: [
          ...rows.map((r) {
            final total = r['amount'] as int;
            final paid = r['paid'] as int;
            final remaining = total - paid;
            final isLend = r['direction'] == 'Cho vay';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.all(13),
                leading: CircleAvatar(
                  backgroundColor: isLend ? const Color(0xFFE5F6ED) : const Color(0xFFFFEEE5),
                  child: Icon(isLend ? Icons.south_west : Icons.north_east, color: isLend ? Colors.green : Colors.deepOrange),
                ),
                title: Text(r['person'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['note']} • ${r['direction']}'),
                    Text('Hạn: ${dateLabel(r['dueDate'] as String?)}'),
                    const SizedBox(height: 5),
                    Text('Còn lại: ${money(remaining)}', style: TextStyle(color: remaining == 0 ? Colors.green : brand, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    LinearProgressIndicator(value: total == 0 ? 0 : paid / total, color: Colors.green, backgroundColor: Colors.black12),
                    Text('Đã trả ${money(paid)} / ${money(total)}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ]),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDebtActions(r),
              ),
            );
          }),
        ]);
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: brand,
      foregroundColor: Colors.white,
      onPressed: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AddDebtPage(db: widget.db)));
        setState(reload);
        widget.onChanged();
      },
      icon: const Icon(Icons.add),
      label: const Text('Thêm khoản'),
    ),
  );

  Future<void> showDebtActions(Map<String, Object?> r) async {
    final id = r['id'] as int;
    final total = r['amount'] as int;
    final paid = r['paid'] as int;
    final rest = total - paid;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['person'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text('${r['note']} • ${r['direction']}'),
          const SizedBox(height: 8),
          Text('Còn lại: ${money(rest)}', style: const TextStyle(color: brand, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.payments_outlined), title: const Text('Ghi nhận thanh toán'), enabled: rest > 0, onTap: () async {
            Navigator.pop(ctx);
            await showPaymentDialog(id, rest);
          }),
          ListTile(leading: const Icon(Icons.history), title: const Text('Lịch sử thanh toán'), onTap: () async {
            Navigator.pop(ctx);
            await showPayments(id);
          }),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Xóa khoản này', style: TextStyle(color: Colors.red)), onTap: () async {
            Navigator.pop(ctx);
            final yes = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
              title: const Text('Xóa khoản vay?'),
              content: const Text('Khoản vay và toàn bộ lịch sử thanh toán của khoản này sẽ bị xóa khỏi máy.'),
              actions: [TextButton(onPressed: ()=>Navigator.pop(dctx, false), child: const Text('Hủy')), FilledButton(onPressed: ()=>Navigator.pop(dctx, true), child: const Text('Xóa'))],
            ));
            if (yes == true) { await widget.db.deleteDebt(id); setState(reload); widget.onChanged(); }
          }),
        ]),
      )),
    );
  }

  Future<void> showPaymentDialog(int id, int remaining) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'Thanh toán');
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Ghi nhận thanh toán'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Số dư còn lại: ${money(remaining)}'),
        const SizedBox(height: 8),
        TextField(controller: amountCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Số tiền đã trả', suffixText: 'đ')),
        TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Ghi chú')),
      ]),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text('Hủy')), FilledButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text('Lưu'))],
    ));
    if (result == true) {
      final value = int.tryParse(amountCtrl.text) ?? 0;
      try {
        await widget.db.addPayment(id, value, noteCtrl.text);
        setState(reload); widget.onChanged();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu thanh toán vào điện thoại.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
    amountCtrl.dispose(); noteCtrl.dispose();
  }

  Future<void> showPayments(int id) async {
    final rows = await widget.db.payments(id);
    if (!mounted) return;
    showModalBottomSheet(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: rows.isEmpty
        ? const SizedBox(height: 100, child: Center(child: Text('Chưa có thanh toán nào.')))
        : ListView(shrinkWrap: true, children: [
            const Text('Lịch sử thanh toán', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            ...rows.map((r) => ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(money(r['amount'] as int), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${r['note']} • ${dateLabel(r['createdAt'] as String)}'),
            )),
          ]),
    )));
  }
}

class AddDebtPage extends StatefulWidget {
  final LocalDatabase db;
  const AddDebtPage({super.key, required this.db});
  @override
  State<AddDebtPage> createState() => _AddDebtPageState();
}

class _AddDebtPageState extends State<AddDebtPage> {
  final person = TextEditingController();
  final note = TextEditingController();
  final amount = TextEditingController();
  String direction = 'Cho vay';
  DateTime? due;
  bool saving = false;

  @override
  void dispose() { person.dispose(); note.dispose(); amount.dispose(); super.dispose(); }

  Future<void> pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(context: context, initialDate: due ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
    if (selected != null) setState(() => due = selected);
  }

  Future<void> save() async {
    final v = int.tryParse(amount.text) ?? 0;
    if (person.text.trim().isEmpty || note.text.trim().isEmpty || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên, nội dung và số tiền hợp lệ.')));
      return;
    }
    setState(() => saving = true);
    await widget.db.addDebt(
      person: person.text,
      note: note.text,
      amount: v,
      direction: direction,
      dueDate: due?.toIso8601String(),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thêm khoản vay')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Thông tin khoản tiền', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      TextField(controller: person, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Tên người liên quan', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'Nội dung / lý do', prefixIcon: Icon(Icons.notes), border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Số tiền (VND)', prefixIcon: Icon(Icons.payments_outlined), suffixText: 'đ', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: direction,
        decoration: const InputDecoration(labelText: 'Loại khoản tiền', border: OutlineInputBorder()),
        items: const [DropdownMenuItem(value: 'Cho vay', child: Text('Mình cho người khác vay')), DropdownMenuItem(value: 'Đi vay', child: Text('Mình đi vay người khác'))],
        onChanged: (v) => setState(() => direction = v ?? 'Cho vay'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: pickDate, icon: const Icon(Icons.calendar_month), label: Text(due == null ? 'Chọn ngày đến hạn (không bắt buộc)' : 'Đến hạn: ${dateLabel(due!.toIso8601String())}')),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save), label: const Padding(padding: EdgeInsets.all(12), child: Text('Lưu vào điện thoại'))),
      const SizedBox(height: 10),
      const Text('Thông tin được lưu cục bộ bằng SQLite, không gửi lên máy chủ.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
    ]),
  );
}

class FeedPage extends StatefulWidget {
  final LocalDatabase db;
  const FeedPage({super.key, required this.db});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() { super.initState(); future = widget.db.posts(); }
  void reload() => setState(() => future = widget.db.posts());

  Future<void> writePost() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Tạo bài viết'),
      content: TextField(controller: ctrl, minLines: 3, maxLines: 5, decoration: const InputDecoration(hintText: 'Bạn đang nghĩ gì?')),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text('Hủy')), FilledButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text('Đăng'))],
    ));
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await widget.db.addPost(ctrl.text);
      reload();
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: pale,
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snap) {
        final posts = snap.data ?? [];
        return ListView(padding: const EdgeInsets.all(14), children: [
          Card(child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFEDE7FF), child: Icon(Icons.person, color: brand)),
            title: const Text('Duy'),
            subtitle: const Text('Chia sẻ một điều tích cực nhé!'),
            trailing: IconButton(onPressed: writePost, icon: const Icon(Icons.add_circle, color: brand, size: 30)),
            onTap: writePost,
          )),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Bài viết trên thiết bị này', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          if (posts.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Chưa có bài viết. Bài đăng ở đây chỉ lưu trên điện thoại này, chưa chia sẻ với người dùng khác.'))),
          ...posts.map((r) => Card(
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [CircleAvatar(backgroundColor: Color(0xFFEDE7FF), child: Icon(Icons.person, color: brand)), SizedBox(width: 10), Text('Duy', style: TextStyle(fontWeight: FontWeight.bold))]),
              const SizedBox(height: 12),
              Text(r['body'] as String),
              const Divider(height: 22),
              const Row(children: [Icon(Icons.favorite_border, size: 19), SizedBox(width: 5), Text('Thích'), SizedBox(width: 22), Icon(Icons.mode_comment_outlined, size: 19), SizedBox(width: 5), Text('Bình luận')]),
            ])),
          )),
        ]);
      },
    ),
    floatingActionButton: FloatingActionButton(onPressed: writePost, backgroundColor: brand, foregroundColor: Colors.white, child: const Icon(Icons.edit)),
  );
}

class PremiumPage extends StatelessWidget {
  const PremiumPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7044D7), Color(0xFFC0A8FA)]), borderRadius: BorderRadius.circular(24)),
      child: const Column(children: [
        Icon(Icons.workspace_premium, color: Colors.white, size: 54),
        SizedBox(height: 8),
        Text('Nợ Bạn Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 25)),
        Text('Mở khóa trải nghiệm quản lý tài chính', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
      ]),
    ),
    const SizedBox(height: 12),
    ...['Không giới hạn khoản vay', 'Nhắc hạn thanh toán tự động', 'Báo cáo và thống kê nâng cao', 'Xuất Excel / PDF', 'Giao diện và sticker độc quyền'].map((s) => ListTile(leading: const Icon(Icons.check_circle, color: brand), title: Text(s))),
    const SizedBox(height: 8),
    _plan(context, 'Premium tháng', '29.000đ / tháng'),
    _plan(context, 'Premium năm', '199.000đ / năm'),
    _plan(context, 'Premium trọn đời', '299.000đ • mua một lần'),
    const Padding(padding: EdgeInsets.all(10), child: Text('Màn hình giá chỉ để thử giao diện. Thanh toán Google Play chưa được tích hợp trong bản offline.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))),
  ]);

  Widget _plan(BuildContext context, String name, String price) => Card(child: ListTile(
    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
    subtitle: Text(price),
    trailing: FilledButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanh toán chưa được bật trong bản thử nghiệm.'))), child: const Text('Chọn')),
  ));
}
