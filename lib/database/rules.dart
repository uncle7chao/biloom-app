part of 'database.dart';

@DataClassName('RawRule')
@TableIndex(name: 'idx_rule_target', columns: {#ruleTarget})
@TableIndex(name: 'idx_rules_profile_order', columns: {#profileId, #order})
class Rules extends Table {
  @override
  String get tableName => 'rules';

  IntColumn get id => integer()();

  IntColumn get profileId => integer().nullable().references(
    Profiles,
    #id,
    onDelete: KeyAction.cascade,
  )();

  TextColumn get ruleAction => textEnum<RuleAction>()();

  TextColumn get content => text().nullable()();

  TextColumn get ruleTarget => text().nullable()();

  TextColumn get ruleProvider => text().nullable()();

  TextColumn get subRule => text().nullable()();

  BoolColumn get noResolve => boolean().withDefault(const Constant(false))();

  BoolColumn get src => boolean().withDefault(const Constant(false))();

  TextColumn get order => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RawDisabledRule')
class DisabledRules extends Table {
  @override
  String get tableName => 'disabled_rules';

  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();

  IntColumn get ruleId =>
      integer().references(Rules, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {profileId, ruleId};
}

@DriftAccessor(tables: [Rules, DisabledRules, Profiles, ProfileRuleLinks])
class RulesDao extends DatabaseAccessor<Database> with _$RulesDaoMixin {
  RulesDao(super.attachedDatabase);

  Selectable<Rule> queryGlobalRules() {
    return _ownedBy(null).map((item) => item.toRule());
  }

  Selectable<Rule> queryProfileRules(int profileId) {
    return _ownedBy(profileId).map((item) => item.toRule());
  }

  Selectable<int> profileRulesCount(int profileId) {
    return _ownedBy(profileId).count;
  }

  Selectable<int> queryDisabledRuleIds(int profileId) {
    final query = selectOnly(disabledRules)
      ..addColumns([disabledRules.ruleId])
      ..where(disabledRules.profileId.equals(profileId));
    return query.map((row) => row.read(disabledRules.ruleId)!);
  }

  /// The profile's own rules come before the global ones it keeps.
  Selectable<Rule> queryAddedRules(int profileId) {
    final disabledIds = selectOnly(disabledRules)
      ..addColumns([disabledRules.ruleId])
      ..where(disabledRules.profileId.equals(profileId));
    final query = rules.select()
      ..where(
        (t) =>
            (t.profileId.isNull() | t.profileId.equals(profileId)) &
            t.id.isNotInQuery(disabledIds),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.profileId.isNull()),
        (t) => OrderingTerm(expression: t.order, nulls: NullsOrder.last),
      ]);
    return query.map((item) => item.toRule());
  }

  SimpleSelectStatement<$RulesTable, RawRule> _ownedBy(int? profileId) {
    return rules.select()
      ..where(
        (t) => profileId == null
            ? t.profileId.isNull()
            : t.profileId.equals(profileId),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.order, nulls: NullsOrder.last),
      ]);
  }

  Future<int> putRule(Rule rule, {int? profileId}) {
    return rules.insertOnConflictUpdate(rule.toCompanion(profileId));
  }

  Future<int> order({required int ruleId, required String order}) {
    final stmt = rules.update()..where((t) => t.id.equals(ruleId));
    return stmt.write(RulesCompanion(order: Value(order)));
  }

  Future<void> delRules(Iterable<int> ruleIds) {
    return batch((b) {
      rules.deleteInChunks(b, ruleIds, (t, chunk) => t.id.isIn(chunk));
    });
  }

  void setProfileRulesWithBatch(int profileId, Batch b, Iterable<Rule> rules) {
    final keys = indexing.generateNKeys(rules.length);
    this.rules.setAll(
      b,
      rules.mapIndexed(
        (index, item) =>
            item.copyWith(order: keys[index]).toCompanion(profileId),
      ),
      deleteFilter: (t) => t.profileId.equals(profileId),
      preDelete: true,
    );
  }

  Future<int> putDisabled(int profileId, int ruleId) {
    return disabledRules.insertOnConflictUpdate(
      DisabledRule(profileId: profileId, ruleId: ruleId).toCompanion(),
    );
  }

  Future<int> delDisabled(int profileId, int ruleId) {
    return disabledRules.remove(
      (t) => t.profileId.equals(profileId) & t.ruleId.equals(ruleId),
    );
  }

  Future<int> renameRuleTarget(
    int profileId, {
    required String oldName,
    required String newName,
  }) {
    final stmt = rules.update()
      ..where((t) => t.profileId.equals(profileId))
      ..where((t) => t.ruleTarget.equals(oldName));
    return stmt.write(RulesCompanion(ruleTarget: Value(newName)));
  }

  Future<Map<int, Set<String>>> targetsNaming(Set<String> names) async {
    final query = selectOnly(rules, distinct: true)
      ..addColumns([rules.profileId, rules.ruleTarget])
      ..where(rules.profileId.isNotNull() & rules.ruleTarget.isIn(names));
    final targets = <int, Set<String>>{};
    for (final row in await query.get()) {
      targets
          .putIfAbsent(row.read(rules.profileId)!, () => {})
          .add(row.read(rules.ruleTarget)!);
    }
    return targets;
  }

  Future<int> renameRuleProvider(
    Iterable<int> profileIds, {
    required String oldName,
    required String newName,
  }) async {
    if (profileIds.isEmpty) {
      return 0;
    }
    final stmt = rules.update()
      ..where((t) => t.profileId.isIn(profileIds))
      ..where(
        (t) =>
            t.ruleAction.equalsValue(RuleAction.RULE_SET) &
            t.ruleProvider.equals(oldName),
      );
    var renamed = await stmt.write(
      RulesCompanion(ruleProvider: Value(newName)),
    );
    final nesting =
        await (rules.select()..where(
              (t) => t.profileId.isIn(profileIds) & _nestingRuleSet(t, oldName),
            ))
            .get();
    for (final row in nesting) {
      final rule = row.toRule();
      if (!rule.ruleSets.contains(oldName)) {
        continue;
      }
      final next = rule.renamedRuleSets({oldName: newName});
      await (rules.update()..where((t) => t.id.equals(row.id))).write(
        RulesCompanion(content: Value(next.content)),
      );
      renamed++;
    }
    return renamed;
  }

  /// A superset of the logic rules nesting [name], narrowed in Dart.
  Expression<bool> _nestingRuleSet($RulesTable t, String name) =>
      t.ruleAction.isInValues([
        for (final action in RuleAction.values)
          if (action.nestsRules) action,
      ]) &
      t.content.like('%$name%');

  /// App-level rule sets are offered to custom profiles only, so a standard
  /// extension naming one means its subscription's own set.
  Future<Set<int>> profileIdsUsingRuleProvider(String provider) async {
    final query =
        selectOnly(rules, distinct: true).join([
            innerJoin(
              profiles,
              profiles.id.equalsExp(rules.profileId),
              useColumns: false,
            ),
          ])
          ..addColumns([
            rules.profileId,
            rules.ruleAction,
            rules.content,
            rules.ruleProvider,
          ])
          ..where(
            profiles.type.equalsValue(ProfileType.custom) &
                (rules.ruleAction.equalsValue(RuleAction.RULE_SET) &
                        rules.ruleProvider.equals(provider) |
                    _nestingRuleSet(rules, provider)),
          );
    return {
      for (final row in await query.get())
        if (Rule(
          ruleAction: row.readWithConverter(rules.ruleAction)!,
          content: row.read(rules.content),
          ruleProvider: row.read(rules.ruleProvider),
        ).ruleSets.contains(provider))
          row.read(rules.profileId)!,
    };
  }

  /// Re-keys [rules] in the order given, since a legacy config's have no key.
  void putAllWithBatch(
    Batch batch,
    Iterable<Rule> rules,
    Iterable<DisabledRule> disabled,
  ) {
    final keys = indexing.generateNKeys(rules.length);
    batch.insertAllOnConflictUpdate(
      this.rules,
      rules.mapIndexed(
        (index, item) => item.copyWith(order: keys[index]).toCompanion(),
      ),
    );
    batch.insertAllOnConflictUpdate(
      disabledRules,
      disabled.map((item) => item.toCompanion()),
    );
  }

  void setAllWithBatch(
    Batch batch,
    Iterable<Rule> rules,
    Iterable<DisabledRule> disabled,
  ) {
    batch.deleteAll(disabledRules);
    batch.deleteAll(this.rules);
    putAllWithBatch(batch, rules, disabled);
  }

  Selectable<Rule> queryGlobalAddedRules() {
    return _query();
  }

  Selectable<Rule> queryProfileAddedRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.added);
  }

  Selectable<Rule> queryProfileDisabledRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.disabled);
  }

  Selectable<Rule> queryProfileCustomRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.custom);
  }

  Selectable<int> profileCustomRulesCount(int profileId) {
    final query = _getSelectStatement(
      profileId: profileId,
      scene: RuleScene.custom,
    );
    return query.count;
  }


  Future<void> resetOrders() async {
    final stmt = profileRuleLinks.select();

    stmt.orderBy([
      (t) => OrderingTerm.asc(t.scene),
      (t) => OrderingTerm.desc(t.order),
      (t) => OrderingTerm.desc(t.id),
    ]);

    final links = await stmt.map((item) => item.toLink()).get();
    final keys = indexing.generateNKeys(links.length);
    await batch((b) {
      b.insertAllOnConflictUpdate(
        profileRuleLinks,
        links.mapIndexed((index, item) => item.toCompanion(keys[index])),
      );
    });
  }

  void _putRulesWithBatch(Batch batch, Iterable<Rule> rules) {
    batch.insertAllOnConflictUpdate(
      this.rules,
      rules.map((item) => item.toCompanion()),
    );
  }

  void _putLinksWithBatch(Batch batch, Iterable<ProfileRuleLink> links) {
    final keys = indexing.generateNKeys(links.length);
    batch.insertAllOnConflictUpdate(
      profileRuleLinks,
      links.mapIndexed((index, item) => item.toCompanion(keys[index])),
    );
  }

  void mergeWithBatch(
    Batch batch,
    Iterable<Rule> rules,
    Iterable<ProfileRuleLink> links,
  ) {
    _putRulesWithBatch(batch, rules);
    _putLinksWithBatch(batch, links);
  }

  void restoreWithBatch(
    Batch batch,
    Iterable<Rule> rules,
    Iterable<ProfileRuleLink> links,
  ) {
    _putRulesWithBatch(batch, rules);
    final ruleIds = rules.map((item) => item.id);
    batch.deleteWhere(this.rules, (t) => t.id.isNotIn(ruleIds));
    _putLinksWithBatch(batch, links);
    final linkKeys = links.map((item) => item.key);
    batch.deleteWhere(profileRuleLinks, (t) => t.id.isNotIn(linkKeys));
  }


  Future<void> putGlobalRule(Rule rule) {
    return _put(rule);
  }

  Future<void> putProfileAddedRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.added);
  }

  Future<void> putProfileCustomRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.custom);
  }

  Future<void> putProfileDisabledRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.disabled);
  }

  void setCustomRulesWithBatch(int profileId, Batch b, Iterable<Rule> rules) {
    _setWithBatch(b, rules, profileId: profileId, scene: RuleScene.custom);
  }

  Future<int> putDisabledLink(int profileId, int ruleId) async {
    return profileRuleLinks.insertOnConflictUpdate(
      ProfileRuleLink(
        ruleId: ruleId,
        profileId: profileId,
        scene: RuleScene.disabled,
      ).toCompanion(),
    );
  }

  Future<bool> delDisabledLink(int profileId, int ruleId) async {
    return profileRuleLinks.deleteOne(
      ProfileRuleLink(
        profileId: profileId,
        ruleId: ruleId,
        scene: RuleScene.disabled,
      ).toCompanion(),
    );
  }

  Future<int> orderGlobalRule({
    required int ruleId,
    required String order,
  }) async {
    return _order(ruleId: ruleId, order: order);
  }

  Future<int> orderProfileAddedRule(
    int profileId, {
    required int ruleId,
    required String order,
  }) async {
    return _order(
      ruleId: ruleId,
      order: order,
      profileId: profileId,
      scene: RuleScene.added,
    );
  }

  Future<int> orderProfileCustomRule(
    int profileId, {
    required int ruleId,
    required String order,
  }) async {
    return _order(
      ruleId: ruleId,
      order: order,
      profileId: profileId,
      scene: RuleScene.custom,
    );
  }

  Future<int> renameCustomRuleTarget(
    int profileId, {
    required String oldName,
    required String newName,
  }) {
    final stmt = rules.update()
      ..where((t) => t.ruleTarget.equals(oldName))
      ..where(
        (t) => t.id.isInQuery(
          selectOnly(profileRuleLinks)
            ..addColumns([profileRuleLinks.ruleId])
            ..where(
              profileRuleLinks.profileId.equals(profileId) &
                  profileRuleLinks.scene.equalsValue(RuleScene.custom),
            ),
        ),
      );
    return stmt.write(RulesCompanion(ruleTarget: Value(newName)));
  }

  JoinedSelectStatement<HasResultSet, dynamic> _getSelectStatement({
    int? profileId,
    RuleScene? scene,
  }) {
    final query = select(rules).join([
      innerJoin(profileRuleLinks, profileRuleLinks.ruleId.equalsExp(rules.id)),
    ]);

    query.where(
      profileId == null
          ? profileRuleLinks.profileId.isNull()
          : profileRuleLinks.profileId.equals(profileId) &
                profileRuleLinks.scene.equalsValue(scene),
    );

    query.orderBy([OrderingTerm.asc(profileRuleLinks.order)]);

    return query;
  }

  Selectable<Rule> _query({int? profileId, RuleScene? scene}) {
    final query = _getSelectStatement(profileId: profileId, scene: scene);

    return query.map((row) {
      return row.readTable(rules).toRule(row.read(profileRuleLinks.order));
    });
  }

  Future<int> _order({
    required int ruleId,
    required String order,
    int? profileId,
    RuleScene? scene,
  }) async {
    final stmt = profileRuleLinks.update();
    stmt.where((t) {
      return (profileId == null
              ? t.profileId.isNull()
              : t.profileId.equals(profileId)) &
          t.ruleId.equals(ruleId) &
          t.scene.equalsValue(scene);
    });
    return stmt.write(ProfileRuleLinksCompanion(order: Value(order)));
  }

  Future<int> _put(Rule rule, {int? profileId, RuleScene? scene}) async {
    return transaction(() async {
      final row = await rules.insertOnConflictUpdate(rule.toCompanion());
      if (row == 0) {
        return 0;
      }
      return profileRuleLinks.insertOnConflictUpdate(
        ProfileRuleLink(
          ruleId: rule.id,
          profileId: profileId,
          scene: scene,
          order: rule.order,
        ).toCompanion(),
      );
    });
  }

  void _setWithBatch(
    Batch b,
    Iterable<Rule> rules, {
    int? profileId,
    RuleScene? scene,
  }) async {
    b.insertAllOnConflictUpdate(
      this.rules,
      rules.map((item) => item.toCompanion()),
    );

    b.deleteWhere(
      profileRuleLinks,
      (t) =>
          (profileId == null
              ? t.profileId.isNull()
              : t.profileId.equals(profileId)) &
          (scene == null ? const Constant(true) : t.scene.equalsValue(scene)),
    );

    final keys = indexing.generateNKeys(rules.length);

    b.insertAllOnConflictUpdate(
      profileRuleLinks,
      rules.mapIndexed(
        (index, item) => ProfileRuleLink(
          ruleId: item.id,
          profileId: profileId,
          scene: scene,
        ).toCompanion(keys[index]),
      ),
    );

    b.deleteWhere(this.rules, (r) {
      final linkedIds = selectOnly(profileRuleLinks);
      linkedIds.addColumns([profileRuleLinks.ruleId]);
      return r.id.isNotInQuery(linkedIds);
    });
  }
}

extension RawRuleExt on RawRule {
  Rule toRule([String? linkOrder]) {
    return Rule(
      id: id,
      profileId: profileId,
      ruleAction: ruleAction,
      content: content,
      ruleTarget: ruleTarget,
      ruleProvider: ruleProvider,
      subRule: subRule,
      noResolve: noResolve,
      src: src,
      order: linkOrder ?? order,
    );
  }
}

extension RulesCompanionExt on Rule {
  RulesCompanion toCompanion([int? profileId]) {
    return RulesCompanion.insert(
      id: Value(id),
      profileId: Value(profileId ?? this.profileId),
      ruleAction: ruleAction,
      content: Value(content),
      ruleTarget: Value(ruleTarget),
      ruleProvider: Value(ruleProvider),
      subRule: Value(subRule),
      noResolve: Value(noResolve),
      src: Value(src),
      order: Value(order),
    );
  }
}

extension RawDisabledRuleExt on RawDisabledRule {
  DisabledRule toDisabledRule() {
    return DisabledRule(profileId: profileId, ruleId: ruleId);
  }
}

extension DisabledRulesCompanionExt on DisabledRule {
  DisabledRulesCompanion toCompanion() {
    return DisabledRulesCompanion.insert(profileId: profileId, ruleId: ruleId);
  }
}
