import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/debug_logger.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../l10n/app_localizations.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final _logger = DebugLogger();
  final _scrollController = ScrollController();
  LogLevel _filterLevel = LogLevel.debug; // Show all by default
  bool _isGeneratingReport = false;

  @override
  void initState() {
    super.initState();
    // Auto-scroll to bottom when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<LogEntry> get _filteredEntries =>
      _logger.entries.where((e) => e.level.index >= _filterLevel.index).toList();

  void _copyLogs() {
    Clipboard.setData(ClipboardData(text: _logger.getAllLogs()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context)!.logsCopied),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareBugReport() async {
    setState(() => _isGeneratingReport = true);

    try {
      final report = await _logger.generateBugReport();

      await Share.share(
        report,
        subject: S.of(context)!.ensembleBugReport,
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingReport = false);
      }
    }
  }

  void _clearLogs() {
    setState(() {
      _logger.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context)!.logsCleared),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _showAllPlayers() async {
    final maProvider = context.read<MusicAssistantProvider>();

    try {
      final allPlayers = await maProvider.getAllPlayersUnfiltered();
      final currentPlayerId = await maProvider.getCurrentPlayerId();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF2a2a2a),
          title: Text(
            S.of(context)!.allPlayersCount(allPlayers.length),
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allPlayers.length,
              itemBuilder: (context, index) {
                final player = allPlayers[index];
                final id = player.playerId.toLowerCase();

                // Detect ghost players: ensemble_*, massiv_*, ma_* prefixes
                final isAppPlayer = id.startsWith('ensemble_') ||
                                    id.startsWith('massiv_') ||
                                    id.startsWith('ma_');
                final isCurrentPlayer = player.playerId == currentPlayerId;
                final isGhost = isAppPlayer && !isCurrentPlayer;
                final isCorrupt = isAppPlayer && !player.available;

                Color cardColor;
                Color textColor;
                IconData? trailingIcon;
                Color? iconColor;

                if (isCurrentPlayer) {
                  cardColor = Colors.green.withOpacity(0.2);
                  textColor = Colors.green[300]!;
                  trailingIcon = Icons.check_circle;
                  iconColor = Colors.green;
                } else if (isCorrupt) {
                  cardColor = Colors.orange.withOpacity(0.2);
                  textColor = Colors.orange[300]!;
                  trailingIcon = Icons.error;
                  iconColor = Colors.orange;
                } else if (isGhost) {
                  cardColor = Colors.red.withOpacity(0.2);
                  textColor = Colors.red[300]!;
                  trailingIcon = Icons.warning;
                  iconColor = Colors.red;
                } else {
                  cardColor = Colors.white.withOpacity(0.1);
                  textColor = Colors.white;
                }

                return Card(
                  color: cardColor,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      player.name,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: (isGhost || isCurrentPlayer) ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.of(context)!.playerId(player.playerId),
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        Text(
                          S.of(context)!.playerInfo(player.available.toString(), player.provider ?? 'unknown'),
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        if (isCurrentPlayer)
                          Text(
                            S.of(context)!.thisDevice,
                            style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        if (isGhost && !isCorrupt)
                          Text(
                            S.of(context)!.ghostPlayer,
                            style: const TextStyle(color: Colors.red, fontSize: 11),
                          ),
                        if (isCorrupt)
                          Text(
                            S.of(context)!.unavailableCorrupt,
                            style: const TextStyle(color: Colors.orange, fontSize: 11),
                          ),
                      ],
                    ),
                    trailing: trailingIcon != null
                        ? Icon(trailingIcon, color: iconColor, size: 20)
                        : null,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final text = allPlayers.map((p) =>
                  'Name: ${p.name}\nID: ${p.playerId}\nAvailable: ${p.available}\nProvider: ${p.provider}\nState: ${p.state}\n---'
                ).join('\n');
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(S.of(context)!.playerListCopied)),
                  );
                }
              },
              child: Text(S.of(context)!.copyList),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.of(context)!.close),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.errorLoadingPlayers(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          color: Colors.white,
        ),
        title: Text(
          S.of(context)!.debugLogs,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        centerTitle: true,
        actions: [
          // Share bug report button
          _isGeneratingReport
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.share_rounded),
                  onPressed: _shareBugReport,
                  color: Colors.white,
                  tooltip: S.of(context)!.shareBugReport,
                ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: S.of(context)!.moreOptions,
            onSelected: (value) async {
              switch (value) {
                case 'show_players':
                  _showAllPlayers();
                  break;
                case 'copy_logs':
                  _copyLogs();
                  break;
                case 'clear_logs':
                  _clearLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'show_players',
                child: ListTile(
                  leading: const Icon(Icons.speaker_group_rounded),
                  title: Text(S.of(context)!.viewAllPlayers),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'copy_logs',
                child: ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: Text(S.of(context)!.copyLogs),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'clear_logs',
                child: ListTile(
                  leading: const Icon(Icons.delete_rounded),
                  title: Text(S.of(context)!.clearLogs),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips and stats
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white.withOpacity(0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Level filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(S.of(context)!.all, LogLevel.debug),
                      const SizedBox(width: 8),
                      _buildFilterChip(S.of(context)!.infoPlus, LogLevel.info),
                      const SizedBox(width: 8),
                      _buildFilterChip(S.of(context)!.warnings, LogLevel.warning),
                      const SizedBox(width: 8),
                      _buildFilterChip(S.of(context)!.errors, LogLevel.error),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Stats
                Text(
                  S.of(context)!.showingEntries(_filteredEntries.length, _logger.entries.length),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: _filteredEntries.isEmpty
                ? Center(
                    child: Text(
                      S.of(context)!.noLogsYet,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(8, 8, 8, BottomSpacing.navBarOnly + 56),
                    itemCount: _filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _filteredEntries[index];
                      return _buildLogEntry(entry);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: BottomSpacing.navBarOnly),
        child: FloatingActionButton(
          onPressed: () {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1a1a1a),
          child: const Icon(Icons.refresh_rounded),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, LogLevel level) {
    final isSelected = _filterLevel == level;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) {
        setState(() {
          _filterLevel = level;
        });
      },
      backgroundColor: Colors.white.withOpacity(0.1),
      selectedColor: _getLevelColor(level).withOpacity(0.3),
      labelStyle: TextStyle(
        color: isSelected ? _getLevelColor(level) : Colors.white70,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? _getLevelColor(level) : Colors.transparent,
      ),
    );
  }

  Widget _buildLogEntry(LogEntry entry) {
    final color = _getLevelColor(entry.level);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        entry.formatted,
        style: TextStyle(
          color: entry.level == LogLevel.error
              ? Colors.red[300]
              : entry.level == LogLevel.warning
                  ? Colors.orange[300]
                  : Colors.white70,
          fontSize: 11,
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.perf:
        return Colors.purple;
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }
}
