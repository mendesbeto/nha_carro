import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedTab = 0;

  Future<void> _logout() async {
    await ApiService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = [
      const _StatCard(
          label: 'Viagens hoje',
          value: '184',
          trend: '+12%',
          accent: Color(0xFF0B8F62)),
      const _StatCard(
          label: 'Receita',
          value: '72.400 CFA',
          trend: '+8.4%',
          accent: Color(0xFF1F8FFF)),
      const _StatCard(
          label: 'Cancelamentos',
          value: '9',
          trend: '-3%',
          accent: Color(0xFFE39A1E)),
      const _StatCard(
          label: 'Motoristas online',
          value: '36',
          trend: '+5',
          accent: Color(0xFF7C4DFF)),
    ];

    final activeTrips = [
      const _TripRow(
          name: 'Aisha P.',
          route: 'Aeroporto → Bandim',
          status: 'Em viagem',
          value: '3.500 CFA'),
      const _TripRow(
          name: 'Mário N.',
          route: 'Mercado → Praia',
          status: 'A recolher',
          value: '2.800 CFA'),
      const _TripRow(
          name: 'Diana K.',
          route: 'Casa → Centro',
          status: 'Concluída',
          value: '1.900 CFA'),
    ];

    final drivers = [
      const _DriverRow(
          name: 'Mamadou S.', rating: '4.9', online: true, trips: '18'),
      const _DriverRow(
          name: 'Abdulai K.', rating: '4.8', online: true, trips: '14'),
      const _DriverRow(
          name: 'Soraia M.', rating: '4.7', online: false, trips: '9'),
    ];

    final passengers = [
      const _PassengerRow(
          name: 'Marta D.',
          activity: '3 viagens hoje',
          status: 'Ativo',
          score: '4.7'),
      const _PassengerRow(
          name: 'João B.',
          activity: '1 reclamação aberta',
          status: 'Alerta',
          score: '4.5'),
      const _PassengerRow(
          name: 'Aisha P.',
          activity: 'Pagamento confirmado',
          status: 'Ativo',
          score: '4.9'),
    ];

    final support = [
      const _SupportRow(title: 'Pagamento pendente', count: '5'),
      const _SupportRow(title: 'Motorista sem resposta', count: '2'),
      const _SupportRow(title: 'Reclamações', count: '3'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Admin'),
        actions: [
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Últimas notificações do sistema')),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notificações',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                    value: 0,
                    label: Text('Resumo'),
                    icon: Icon(Icons.dashboard_outlined)),
                ButtonSegment<int>(
                    value: 1,
                    label: Text('Motoristas'),
                    icon: Icon(Icons.drive_eta_outlined)),
                ButtonSegment<int>(
                    value: 2,
                    label: Text('Clientes'),
                    icon: Icon(Icons.people_outline_rounded)),
                ButtonSegment<int>(
                    value: 3,
                    label: Text('Financeiro'),
                    icon: Icon(Icons.account_balance_wallet_outlined)),
                ButtonSegment<int>(
                    value: 4,
                    label: Text('Suporte'),
                    icon: Icon(Icons.support_agent_outlined)),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (selection) =>
                  setState(() => _selectedTab = selection.first),
            ),
          ),
          Expanded(
            child: _selectedTab == 0
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                    children: [
                      const Text('Resumo operacional',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 16),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.4,
                        children: stats,
                      ),
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.bar_chart_rounded,
                                      color: Color(0xFF0B8F62)),
                                  SizedBox(width: 8),
                                  Text('Atividade em tempo real',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                              const SizedBox(height: 14),
                              const Text('Taxa de sucesso: 96.2%',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: const LinearProgressIndicator(
                                  value: 0.962,
                                  minHeight: 10,
                                  backgroundColor: Color(0xFFE5E7EB),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF0B8F62)),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Row(
                                children: [
                                  Expanded(
                                      child: _MiniMetric(
                                          label: 'Tempo médio',
                                          value: '11 min')),
                                  SizedBox(width: 10),
                                  Expanded(
                                      child: _MiniMetric(
                                          label: 'Avaliação', value: '4.8 ★')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.insights_rounded,
                                      color: Color(0xFF0B8F62)),
                                  SizedBox(width: 8),
                                  Text('Receita da semana',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                              SizedBox(height: 18),
                              SizedBox(
                                height: 160,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _ChartColumn(
                                        day: 'Seg', value: 0.42, amount: '12k'),
                                    _ChartColumn(
                                        day: 'Ter', value: 0.66, amount: '18k'),
                                    _ChartColumn(
                                        day: 'Qua', value: 0.58, amount: '16k'),
                                    _ChartColumn(
                                        day: 'Qui', value: 0.84, amount: '25k'),
                                    _ChartColumn(
                                        day: 'Sex', value: 0.73, amount: '21k'),
                                    _ChartColumn(
                                        day: 'Sáb', value: 0.95, amount: '31k'),
                                    _ChartColumn(
                                        day: 'Dom', value: 0.69, amount: '20k'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                              child: _SectionTitle(title: 'Viagens em curso')),
                          TextButton(
                              onPressed: () {}, child: const Text('Ver tudo')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...activeTrips.map((trip) => _TripCard(trip: trip)),
                    ],
                  )
                : _selectedTab == 1
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                        children: [
                          const _SectionTitle(title: 'Motoristas'),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: drivers
                                    .map(
                                        (driver) => _DriverTile(driver: driver))
                                    .toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Nova revisão de desempenho foi agendada.')),
                            ),
                            icon: const Icon(Icons.sync_rounded),
                            label: const Text('Sincronizar motoristas'),
                          ),
                        ],
                      )
                    : _selectedTab == 2
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                            children: [
                              const _SectionTitle(title: 'Clientes'),
                              const SizedBox(height: 12),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    children: passengers
                                        .map((passenger) => _PassengerTile(
                                            passenger: passenger))
                                        .toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () =>
                                    ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Lista de clientes foi atualizada.')),
                                ),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Atualizar clientes'),
                              ),
                            ],
                          )
                        : _selectedTab == 3
                            ? ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 6, 20, 28),
                                children: [
                                  const _SectionTitle(title: 'Financeiro'),
                                  const SizedBox(height: 12),
                                  const Row(
                                    children: [
                                      Expanded(
                                          child: _MiniMetric(
                                              label: 'Lucro bruto',
                                              value: '53.600 CFA')),
                                      SizedBox(width: 10),
                                      Expanded(
                                          child: _MiniMetric(
                                              label: 'Comissão',
                                              value: '18.800 CFA')),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Distribuição por método',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w800)),
                                          SizedBox(height: 16),
                                          _PaymentRow(
                                              label: 'Dinheiro',
                                              value: '42%',
                                              amount: '30.000 CFA'),
                                          _PaymentRow(
                                              label: 'Orange Money',
                                              value: '35%',
                                              amount: '25.000 CFA'),
                                          _PaymentRow(
                                              label: 'MTN Mobile',
                                              value: '23%',
                                              amount: '17.400 CFA'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Relatório financeiro foi exportado.')),
                                    ),
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Exportar relatório'),
                                  ),
                                ],
                              )
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 6, 20, 28),
                                children: [
                                  const _SectionTitle(
                                      title: 'Suporte e alertas'),
                                  const SizedBox(height: 12),
                                  Card(
                                    child: Column(
                                      children: support
                                          .map((item) => ListTile(
                                                leading: const Icon(
                                                    Icons
                                                        .report_problem_outlined,
                                                    color: Color(0xFFE39A1E)),
                                                title: Text(item.title),
                                                trailing: Text(item.count,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800)),
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const _SectionTitle(
                                      title: 'Passageiros com atenção'),
                                  const SizedBox(height: 12),
                                  const Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Column(
                                        children: [
                                          _PassengerTile(
                                              passenger: _PassengerRow(
                                            name: 'Marta D.',
                                            activity:
                                                'Pagamento pendente • 3 viagens',
                                            status: 'Atenção',
                                            score: '4.7',
                                          )),
                                          _PassengerTile(
                                              passenger: _PassengerRow(
                                            name: 'João B.',
                                            activity:
                                                'Reclamação aberta • 1 viagem',
                                            status: 'Atenção',
                                            score: '4.5',
                                          )),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Equipe de suporte foi notificada.')),
                                    ),
                                    icon:
                                        const Icon(Icons.support_agent_rounded),
                                    label: const Text('Alertar suporte'),
                                  ),
                                ],
                              ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.trend,
    required this.accent,
  });

  final String label;
  final String value;
  final String trend;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.trending_up_rounded, color: accent, size: 18),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 6),
            Text(value,
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(trend,
                style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
  }
}

class _TripRow {
  const _TripRow(
      {required this.name,
      required this.route,
      required this.status,
      required this.value});

  final String name;
  final String route;
  final String status;
  final String value;
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final _TripRow trip;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: Color(0xFFDDF5EA),
              child: Icon(Icons.person, color: Color(0xFF0B8F62)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(trip.route,
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    trip.status,
                    style: const TextStyle(
                        color: Color(0xFF0B8F62),
                        fontWeight: FontWeight.w700,
                        fontSize: 11),
                  ),
                ),
                const SizedBox(height: 6),
                Text(trip.value,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverRow {
  const _DriverRow(
      {required this.name,
      required this.rating,
      required this.online,
      required this.trips});

  final String name;
  final String rating;
  final bool online;
  final String trips;
}

class _DriverTile extends StatelessWidget {
  const _DriverTile({required this.driver});

  final _DriverRow driver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFDDF5EA),
            child: Icon(Icons.drive_eta_rounded, color: Color(0xFF0B8F62)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driver.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Avaliação: ${driver.rating} • ${driver.trips} viagens',
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: driver.online
                  ? const Color(0xFFE7F8F0)
                  : const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              driver.online ? 'Online' : 'Offline',
              style: TextStyle(
                color: driver.online ? const Color(0xFF0B8F62) : Colors.black54,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportRow {
  const _SupportRow({required this.title, required this.count});

  final String title;
  final String count;
}

class _PassengerRow {
  const _PassengerRow({
    required this.name,
    required this.activity,
    required this.status,
    required this.score,
  });

  final String name;
  final String activity;
  final String status;
  final String score;
}

class _PassengerTile extends StatelessWidget {
  const _PassengerTile({required this.passenger});

  final _PassengerRow passenger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFDDF5EA),
            child: Icon(Icons.person_outline, color: Color(0xFF0B8F62)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(passenger.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(passenger.activity,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(passenger.score,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  passenger.status,
                  style: const TextStyle(
                      color: Color(0xFF0B8F62),
                      fontWeight: FontWeight.w700,
                      fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.value,
    required this.amount,
  });

  final String label;
  final String value;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: double.parse(value.replaceAll('%', '')) / 100,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF0B8F62)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Text(value,
              style: const TextStyle(
                  color: Colors.black54, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ChartColumn extends StatelessWidget {
  const _ChartColumn({
    required this.day,
    required this.value,
    required this.amount,
  });

  final String day;
  final double value;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Text(amount,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 0.9,
                  heightFactor: value,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0B8F62),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(day,
                style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
