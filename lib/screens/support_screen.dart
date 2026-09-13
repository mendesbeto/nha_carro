import 'package:flutter/material.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {
      'isUser': false,
      'text': 'Olá! Como posso ajudar hoje?',
    },
    {
      'isUser': false,
      'text': 'Posso ajudar com pagamento, viagem, segurança e conta.',
    },
  ];

  String _generateAutoReply(String text) {
    final lower = text.toLowerCase();

    if (lower.contains('pagamento') || lower.contains('carteira')) {
      return 'O suporte financeiro revisou o seu caso. Verifique a carteira e, se a cobrança não estiver refletida em 15 minutos, confirme os dados do pagamento.';
    }
    if (lower.contains('viagem') || lower.contains('rota') || lower.contains('rast')) {
      return 'A sua viagem está em análise. Se o motorista não chegou em 10 minutos, pode activar a ajuda urgente ou pedir uma nova atribuição.';
    }
    if (lower.contains('seguran') || lower.contains('sos') || lower.contains('emerg')) {
      return 'A sua segurança é prioritária. Mantenha-se numa zona pública e confirme a sua localização. O suporte NhaCarro está a reforçar o contacto de emergência.';
    }
    if (lower.contains('perfil') || lower.contains('conta') || lower.contains('dados')) {
      return 'Pode atualizar os seus dados de conta na aba Perfil. Se tiver bloqueio de acesso, podemos confirmar a recuperação da conta.';
    }
    return 'Recebemos a sua mensagem. O suporte responderá em breve e pode também abrir um pedido de emergência se esta questão for urgente.';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'isUser': true, 'text': text});
    });
    _messageController.clear();

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isUser': false,
          'text': _generateAutoReply(text),
        });
      });
    });
  }

  void _showEmergencyHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajuda de emergência'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A sua localização foi marcada para contacto prioritário. O apoio NhaCarro reforçou a sua segurança e verificará o estado da viagem.',
            ),
            SizedBox(height: 12),
            Text(
              'Ações recomendadas: mantenha-se numa zona pública, ligue para a polícia local se houver risco imediato e siga as instruções da equipa de apoio.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final helpTopics = [
      {
        'title': 'Pagamento e carteira',
        'subtitle': 'Carregar saldo, pagamentos e devoluções.',
        'icon': Icons.account_balance_wallet_rounded,
      },
      {
        'title': 'Viagens e rastreio',
        'subtitle': 'Ajuda com corrida, rota e acompanhamento.',
        'icon': Icons.map_rounded,
      },
      {
        'title': 'Segurança',
        'subtitle': 'Denúncias, apoio e procedimentos de emergência.',
        'icon': Icons.shield_rounded,
      },
      {
        'title': 'Conta e perfil',
        'subtitle': 'Atualizar dados e gestão da conta.',
        'icon': Icons.person_rounded,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Central de ajuda'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Precisa de ajuda?',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Escolha um tema ou fale diretamente com o nosso suporte.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 120,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: helpTopics.map((topic) {
                    final title = topic['title'] as String;
                    final icon = topic['icon'] as IconData;
                    return SizedBox(
                      width: 180,
                      child: Card(
                        child: InkWell(
                          onTap: () {
                            _messageController.text = title;
                            _sendMessage();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon, color: const Color(0xFF0B8F62)),
                                const SizedBox(height: 8),
                                Text(
                                  title,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _showEmergencyHelp,
                  icon: const Icon(Icons.emergency_outlined),
                  label: const Text('Ajuda urgente / SOS'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB42318),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message['isUser'] as bool;

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          constraints: const BoxConstraints(maxWidth: 260),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFF0B8F62)
                                : const Color(0xFFF1F5F3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            message['text'] as String,
                            style: TextStyle(
                              color: isUser ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Escreva sua mensagem',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _sendMessage,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
