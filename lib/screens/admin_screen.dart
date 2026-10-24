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
                      const SizedBox(height: 8),
                      const Text(
                        'Os indicadores de viagens, receita e atividade em tempo real ainda não estão ligados aos dados de produção. Para evitar números fictícios, o resumo apresenta apenas dados reais disponíveis.',
                      ),
                      const SizedBox(height: 16),
                      _AdminUserCountCard(
                        title: 'Motoristas registados',
                        icon: Icons.drive_eta_outlined,
                        future: driversFuture,
                      ),
                      const SizedBox(height: 12),
                      _AdminUserCountCard(
                        title: 'Clientes registados',
                        icon: Icons.people_outline_rounded,
                        future: passengersFuture,
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'As estatísticas de viagens, receita, cancelamentos, avaliação e atividade semanal serão apresentadas quando existir uma ligação validada aos respetivos dados.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
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
                                  )
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
