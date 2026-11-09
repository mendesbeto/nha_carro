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


    final driversFuture = ApiService().getAdminUsers('MOTORISTA');
    final passengersFuture = ApiService().getAdminUsers('PASSAGEIRO');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Admin'),
        actions: [
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('As notificações ainda não estão ligadas ao sistema.')),
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
                    label: Text('Corridas'),
                    icon: Icon(Icons.receipt_long_outlined)),
                ButtonSegment<int>(
                    value: 5,
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
                ? const _AdminSummaryPanel()
                : _selectedTab == 1
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                        children: [
                          const _SectionTitle(title: 'Motoristas'),
                          const SizedBox(height: 12),
                          FutureBuilder<Map<String, dynamic>>(
                            future: driversFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                              }
                              if (snapshot.hasError) {
                                return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Erro ao carregar motoristas: ${snapshot.error}')));
                              }
                              final users = (snapshot.data?['users'] as List? ?? const []).whereType<Map>().map((u) => Map<String, dynamic>.from(u)).toList();
                              if (users.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Ainda não existem motoristas registados.')));
                              return Card(child: Column(children: users.map((u) => ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.drive_eta_outlined)),
                                title: Text((u['nome'] as String?)?.trim().isNotEmpty == true ? u['nome'] as String : 'Motorista sem nome'),
                                subtitle: Text('${u['telefone'] ?? 'Sem telefone'} • ${u['status_conta'] ?? 'Estado desconhecido'}'),
                                trailing: Text(u['avaliacao_media'] == null ? '—' : '${u['avaliacao_media']} ★'),
                              )).toList()));
                            },
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => setState(() {}),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Atualizar lista'),
                          ),
                        ],
                      )
                    : _selectedTab == 2
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                            children: [
                              const _SectionTitle(title: 'Clientes'),
                              const SizedBox(height: 12),
                              FutureBuilder<Map<String, dynamic>>(
                                future: passengersFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                                  }
                                  if (snapshot.hasError) {
                                    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Erro ao carregar clientes: ${snapshot.error}')));
                                  }
                                  final users = (snapshot.data?['users'] as List? ?? const []).whereType<Map>().map((u) => Map<String, dynamic>.from(u)).toList();
                                  if (users.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Ainda não existem clientes registados.')));
                                  return Card(child: Column(children: users.map((u) => ListTile(
                                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                                    title: Text((u['nome'] as String?)?.trim().isNotEmpty == true ? u['nome'] as String : 'Cliente sem nome'),
                                    subtitle: Text('${u['telefone'] ?? 'Sem telefone'} • ${u['status_conta'] ?? 'Estado desconhecido'}'),
                                    trailing: const Icon(Icons.verified_user_outlined),
                                  )).toList()));
                                },
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => setState(() {}),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Atualizar clientes'),
                              ),
                            ],
                          )
                        : _selectedTab == 3
                            ? ListView(
                                padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                                children: [
                                  const _SectionTitle(title: 'Financeiro'),
                                  const SizedBox(height: 12),
                                  const _CommissionDebtPanel(),
                                  const SizedBox(height: 16),
                                  const Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.info_outline_rounded),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Os totais de receita, lucro e distribuição por método de pagamento ainda não estão ligados a uma fonte de dados validada. Os valores fictícios foram removidos.',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Exportação indisponível'),
                                  ),
                                ],
                              )
                            : _selectedTab == 4
                        ? const _AdminRidesPanel()
                        : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 6, 20, 28),
                                children: [
                                  const _SectionTitle(
                                      title: 'Suporte e alertas'),
                                  const SizedBox(height: 12),
                                  const Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'Os alertas e contadores de suporte ainda não estão ligados ao sistema de atendimento. Nenhum número fictício é apresentado.',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const _SectionTitle(
                                      title: 'Passageiros com atenção'),
                                  const SizedBox(height: 12),
                                  const Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(
                                        'Os alertas reais de passageiros serão apresentados aqui quando estiverem ligados ao serviço de suporte.',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.support_agent_rounded),
                                    label: const Text('Alertas indisponíveis'),
                                  )
                                ],
                              ),
          ),
        ],
      ),
    );
  }
}


class _AdminUserCountCard extends StatelessWidget {
  const _AdminUserCountCard({
    required this.title,
    required this.icon,
    required this.future,
  });

  final String title;
  final IconData icon;
  final Future<Map<String, dynamic>> future;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          String value;
          if (snapshot.connectionState == ConnectionState.waiting) {
            value = 'A carregar…';
          } else if (snapshot.hasError) {
            value = 'Indisponível';
          } else {
            final users = (snapshot.data?['users'] as List? ?? const []);
            value = users.length.toString();
          }
          return ListTile(
            leading: CircleAvatar(child: Icon(icon)),
            title: Text(title),
            trailing: Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          );
        },
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

class _CommissionDebtPanel extends StatefulWidget {
  const _CommissionDebtPanel();

  @override
  State<_CommissionDebtPanel> createState() => _CommissionDebtPanelState();
}

class _CommissionDebtPanelState extends State<_CommissionDebtPanel> {
  late Future<Map<String, dynamic>> _debtsFuture;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _debtsFuture = ApiService().getAdminCommissionDebts();
  }

  void _reload() {
    setState(() {
      _debtsFuture = ApiService().getAdminCommissionDebts();
    });
  }

  Future<void> _confirmSettlement(Map<String, dynamic> debt) async {
    final debtId = debt['id'] as String?;
    if (debtId == null || _settling) return;

    var paymentMethod = 'DINHEIRO';
    final referenceController = TextEditingController();
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Confirmar recebimento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Comissão: ${debt['valor']} CFA'),
              const SizedBox(height: 12),
              const Text(
                'Confirme apenas se o pagamento já foi efetivamente recebido.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: const InputDecoration(labelText: 'Método de pagamento'),
                items: const [
                  DropdownMenuItem(value: 'DINHEIRO', child: Text('Dinheiro')),
                  DropdownMenuItem(value: 'TRANSFERENCIA', child: Text('Transferência')),
                  DropdownMenuItem(value: 'OUTRO', child: Text('Outro')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => paymentMethod = value);
                  }
                },
              ),
              if (paymentMethod == 'TRANSFERENCIA') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Referência da transferência',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final reference = referenceController.text.trim();
                if (paymentMethod == 'TRANSFERENCIA' && reference.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Informe a referência da transferência.'),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop({
                  'method': paymentMethod,
                  'reference': reference,
                });
              },
              child: const Text('Confirmar recebimento'),
            ),
          ],
        ),
      ),
    );
    referenceController.dispose();

    if (details == null || !mounted) return;

    setState(() => _settling = true);
    try {
      final result = await ApiService().settleCommissionDebt(
        debtId: debtId,
        paymentMethod: details['method']!,
        paymentReference: details['reference'],
      );
      if (!mounted) return;
      final alreadyPaid = result['alreadyPaid'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyPaid
                ? 'Esta comissão já estava liquidada.'
                : 'Pagamento de comissão registado com sucesso.',
          ),
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _settling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _debtsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comissões pendentes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text('Não foi possível carregar as dívidas.'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ),
                ],
              );
            }

            final data = snapshot.data ?? <String, dynamic>{};
            final debts = (data['debts'] as List? ?? const [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where((item) => item['status'] == 'PENDENTE')
                .toList();
            final total = double.tryParse('${data['pendingTotal']}') ?? 0;
            final count = data['pendingCount'] as int? ?? debts.length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Comissões pendentes',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: _settling ? null : _reload,
                      tooltip: 'Atualizar',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                Text(
                  '${total.toStringAsFixed(0)} CFA por receber • $count dívida(s)',
                  style: const TextStyle(
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (debts.isEmpty)
                  const Text('Não existem comissões pendentes.')
                else
                  ...debts.take(10).map((debt) {
                    final driver = debt['motorista'] is Map
                        ? Map<String, dynamic>.from(debt['motorista'] as Map)
                        : <String, dynamic>{};
                    final driverName = driver['nome'] as String? ?? 'Motorista';
                    final driverPhone = driver['telefone'] as String? ?? '';
                    final amount = double.tryParse('${debt['valor']}') ?? 0;
                    final rideId = debt['corrida_id'] as String? ?? '';
                    return Column(
                      children: [
                        const Divider(height: 20),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.receipt_long_outlined),
                          ),
                          title: Text(driverName),
                          subtitle: Text(
                            '${amount.toStringAsFixed(0)} CFA • Corrida ${rideId.isEmpty ? '—' : rideId.substring(0, rideId.length > 8 ? 8 : rideId.length)}'
                            '${driverPhone.isEmpty ? '' : '\n$driverPhone'}',
                          ),
                          isThreeLine: driverPhone.isNotEmpty,
                          trailing: _settling
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  tooltip: 'Registar pagamento recebido',
                                  onPressed: () => _confirmSettlement(debt),
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    color: Color(0xFF0B8F62),
                                  ),
                                ),
                        ),
                      ],
                    );
                  }),
                if (debts.length > 10)
                  Text('A mostrar 10 de ${debts.length} dívidas pendentes.'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminRidesPanel extends StatefulWidget {
  const _AdminRidesPanel();

  @override
  State<_AdminRidesPanel> createState() => _AdminRidesPanelState();
}

class _AdminRidesPanelState extends State<_AdminRidesPanel> {
  late Future<List<Map<String, dynamic>>> _ridesFuture;

  @override
  void initState() {
    super.initState();
    _ridesFuture = ApiService().getAdminRideHistory();
  }

  void _reload() {
    setState(() {
      _ridesFuture = ApiService().getAdminRideHistory();
    });
  }

  String _dateLabel(dynamic raw) {
    final date = DateTime.tryParse('$raw');
    if (date == null) return 'Data indisponível';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'CONCLUIDA':
        return 'Concluída';
      case 'EM_ANDAMENTO':
        return 'Em andamento';
      case 'ACEITA':
        return 'Aceite';
      case 'SOLICITADA':
        return 'Solicitada';
      case 'CANCELADA':
        return 'Cancelada';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: _SectionTitle(title: 'Histórico de corridas'),
            ),
            IconButton(
              onPressed: _reload,
              tooltip: 'Atualizar corridas',
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Últimas 100 corridas, incluindo as concluídas.'),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _ridesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Erro ao carregar corridas: ${snapshot.error}',
                  ),
                ),
              );
            }
            final rides = snapshot.data ?? const <Map<String, dynamic>>[];
            if (rides.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Ainda não existem corridas registadas.'),
                ),
              );
            }
            return Card(
              child: Column(
                children: rides.map((ride) {
                  final passenger = ride['passageiro'] is Map
                      ? Map<String, dynamic>.from(ride['passageiro'] as Map)
                      : <String, dynamic>{};
                  final driver = ride['motorista'] is Map
                      ? Map<String, dynamic>.from(ride['motorista'] as Map)
                      : <String, dynamic>{};
                  final rideId = '${ride['rideId'] ?? ''}';
                  final amount = double.tryParse('${ride['valor']}') ?? 0;
                  final status = '${ride['status'] ?? 'DESCONHECIDO'}';
                  final payment = '${ride['formaPagamento'] ?? '—'}';
                  final passengerName =
                      passenger['nome'] as String? ?? 'Passageiro';
                  final driverName =
                      driver['nome'] as String? ?? 'Não atribuído';

                  return Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            status == 'CONCLUIDA'
                                ? Icons.check_circle_outline
                                : Icons.local_taxi_outlined,
                          ),
                        ),
                        title: Text(
                          '${amount.toStringAsFixed(0)} CFA • ${_statusLabel(status)}',
                        ),
                        subtitle: Text(
                          'Passageiro: $passengerName\n'
                          'Motorista: $driverName\n'
                          'Pagamento: $payment • ${_dateLabel(ride['criadoEm'])}'
                          '${rideId.isEmpty ? '' : '\nID: ${rideId.substring(0, rideId.length > 8 ? 8 : rideId.length)}'}',
                        ),
                        isThreeLine: true,
                      ),
                      if (ride != rides.last) const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AdminSummaryPanel extends StatefulWidget {
  const _AdminSummaryPanel();

  @override
  State<_AdminSummaryPanel> createState() => _AdminSummaryPanelState();
}

class _AdminSummaryPanelState extends State<_AdminSummaryPanel> {
  late Future<Map<String, dynamic>> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = ApiService().getAdminSummary();
  }

  void _reload() {
    setState(() {
      _summaryFuture = ApiService().getAdminSummary();
    });
  }

  String _number(dynamic value) {
    final number = (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0;
    return number.toStringAsFixed(number == number.roundToDouble() ? 0 : 1);
  }

  Widget _metric(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Resumo operacional', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Não foi possível carregar os indicadores reais: ${snapshot.error}'))),
              FilledButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
            ],
          );
        }
        final data = snapshot.data ?? <String, dynamic>{};
        final users = Map<String, dynamic>.from(data['users'] as Map? ?? {});
        final rides = Map<String, dynamic>.from(data['rides'] as Map? ?? {});
        final financial = Map<String, dynamic>.from(data['financial'] as Map? ?? {});
        final activity = (data['weeklyActivity'] as List? ?? const [])
            .whereType<Map>()
            .map((day) => Map<String, dynamic>.from(day))
            .toList();
        final maxDaily = activity.fold<int>(0, (max, day) {
          final count = (day['total'] as num?)?.toInt() ?? 0;
          return count > max ? count : max;
        });
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            Row(
              children: [
                const Expanded(child: Text('Resumo operacional', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                IconButton(onPressed: _reload, tooltip: 'Atualizar indicadores', icon: const Icon(Icons.refresh_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Indicadores calculados a partir dos registos reais de produção.'),
            const SizedBox(height: 16),
            _metric('Corridas registadas', _number(rides['total']), Icons.local_taxi_outlined),
            _metric('Corridas concluídas', _number(rides['completed']), Icons.check_circle_outline),
            _metric('Corridas canceladas', _number(rides['cancelled']), Icons.cancel_outlined),
            _metric('Corridas em curso/pendentes', _number(rides['active']), Icons.pending_actions_outlined),
            _metric('Valor bruto das corridas concluídas', '${_number(financial['grossCompleted'])} CFA', Icons.payments_outlined),
            _metric('Comissões geradas', '${_number(financial['commissionsAccrued'])} CFA', Icons.account_balance_wallet_outlined),
            _metric('Valor médio por corrida concluída', '${_number(financial['averageCompletedFare'])} CFA', Icons.trending_up_rounded),
            _metric('Motoristas registados', _number(users['drivers']), Icons.drive_eta_outlined),
            _metric('Clientes registados', _number(users['passengers']), Icons.people_outline_rounded),
            const SizedBox(height: 12),
            const _SectionTitle(title: 'Atividade dos últimos 7 dias'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: activity.isEmpty
                    ? const Text('Sem atividade registada neste período.')
                    : Column(
                        children: activity.map((day) {
                          final total = (day['total'] as num?)?.toInt() ?? 0;
                          final completed = (day['completed'] as num?)?.toInt() ?? 0;
                          final cancelled = (day['cancelled'] as num?)?.toInt() ?? 0;
                          final date = DateTime.tryParse('${day['date']}');
                          final label = date == null ? '${day['date']}' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
                          final ratio = maxDaily == 0 ? 0.0 : total / maxDaily;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(width: 48, child: Text(label)),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(value: ratio, minHeight: 10),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('$total • ${completed} concl. • ${cancelled} canc.'),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              financial['note']?.toString() ?? 'Os valores financeiros são informativos.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text('Atualizado: ${data['generatedAt'] ?? '—'}', style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

