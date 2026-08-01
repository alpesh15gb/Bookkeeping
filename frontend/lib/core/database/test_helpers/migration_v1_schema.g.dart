// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_v1_schema.dart';

// ignore_for_file: type=lint
class $JournalEntriesV1Table extends JournalEntriesV1
    with TableInfo<$JournalEntriesV1Table, JournalEntriesV1Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalEntriesV1Table(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryDateMeta = const VerificationMeta(
    'entryDate',
  );
  @override
  late final GeneratedColumn<String> entryDate = GeneratedColumn<String>(
    'entry_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _referenceNumberMeta = const VerificationMeta(
    'referenceNumber',
  );
  @override
  late final GeneratedColumn<String> referenceNumber = GeneratedColumn<String>(
    'reference_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('MANUAL'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('DRAFT'),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('localOnly'),
  );
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remoteRevisionMeta = const VerificationMeta(
    'remoteRevision',
  );
  @override
  late final GeneratedColumn<int> remoteRevision = GeneratedColumn<int>(
    'remote_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncErrorMeta = const VerificationMeta(
    'syncError',
  );
  @override
  late final GeneratedColumn<String> syncError = GeneratedColumn<String>(
    'sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'is_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  @override
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    remoteId,
    companyId,
    entryDate,
    referenceNumber,
    description,
    sourceType,
    status,
    syncStatus,
    localRevision,
    remoteRevision,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
    syncError,
    isDirty,
    originDeviceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalEntriesV1Data> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('entry_date')) {
      context.handle(
        _entryDateMeta,
        entryDate.isAcceptableOrUnknown(data['entry_date']!, _entryDateMeta),
      );
    } else if (isInserting) {
      context.missing(_entryDateMeta);
    }
    if (data.containsKey('reference_number')) {
      context.handle(
        _referenceNumberMeta,
        referenceNumber.isAcceptableOrUnknown(
          data['reference_number']!,
          _referenceNumberMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    }
    if (data.containsKey('remote_revision')) {
      context.handle(
        _remoteRevisionMeta,
        remoteRevision.isAcceptableOrUnknown(
          data['remote_revision']!,
          _remoteRevisionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('sync_error')) {
      context.handle(
        _syncErrorMeta,
        syncError.isAcceptableOrUnknown(data['sync_error']!, _syncErrorMeta),
      );
    }
    if (data.containsKey('is_dirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['is_dirty']!, _isDirtyMeta),
      );
    }
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  JournalEntriesV1Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalEntriesV1Data(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      ),
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      entryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_date'],
      )!,
      referenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_number'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      remoteRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_revision'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      ),
      syncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_error'],
      ),
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dirty'],
      )!,
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      )!,
    );
  }

  @override
  $JournalEntriesV1Table createAlias(String alias) {
    return $JournalEntriesV1Table(attachedDatabase, alias);
  }
}

class JournalEntriesV1Data extends DataClass
    implements Insertable<JournalEntriesV1Data> {
  final String localId;
  final String? remoteId;
  final String companyId;
  final String entryDate;
  final String? referenceNumber;
  final String description;
  final String sourceType;
  final String status;
  final String syncStatus;
  final int localRevision;
  final int? remoteRevision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? lastSyncedAt;
  final String? syncError;
  final bool isDirty;
  final String originDeviceId;
  const JournalEntriesV1Data({
    required this.localId,
    this.remoteId,
    required this.companyId,
    required this.entryDate,
    this.referenceNumber,
    required this.description,
    required this.sourceType,
    required this.status,
    required this.syncStatus,
    required this.localRevision,
    this.remoteRevision,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.lastSyncedAt,
    this.syncError,
    required this.isDirty,
    required this.originDeviceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    map['company_id'] = Variable<String>(companyId);
    map['entry_date'] = Variable<String>(entryDate);
    if (!nullToAbsent || referenceNumber != null) {
      map['reference_number'] = Variable<String>(referenceNumber);
    }
    map['description'] = Variable<String>(description);
    map['source_type'] = Variable<String>(sourceType);
    map['status'] = Variable<String>(status);
    map['sync_status'] = Variable<String>(syncStatus);
    map['local_revision'] = Variable<int>(localRevision);
    if (!nullToAbsent || remoteRevision != null) {
      map['remote_revision'] = Variable<int>(remoteRevision);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    }
    if (!nullToAbsent || syncError != null) {
      map['sync_error'] = Variable<String>(syncError);
    }
    map['is_dirty'] = Variable<bool>(isDirty);
    map['origin_device_id'] = Variable<String>(originDeviceId);
    return map;
  }

  JournalEntriesV1Companion toCompanion(bool nullToAbsent) {
    return JournalEntriesV1Companion(
      localId: Value(localId),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
      companyId: Value(companyId),
      entryDate: Value(entryDate),
      referenceNumber: referenceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceNumber),
      description: Value(description),
      sourceType: Value(sourceType),
      status: Value(status),
      syncStatus: Value(syncStatus),
      localRevision: Value(localRevision),
      remoteRevision: remoteRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteRevision),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      syncError: syncError == null && nullToAbsent
          ? const Value.absent()
          : Value(syncError),
      isDirty: Value(isDirty),
      originDeviceId: Value(originDeviceId),
    );
  }

  factory JournalEntriesV1Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalEntriesV1Data(
      localId: serializer.fromJson<String>(json['localId']),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
      companyId: serializer.fromJson<String>(json['companyId']),
      entryDate: serializer.fromJson<String>(json['entryDate']),
      referenceNumber: serializer.fromJson<String?>(json['referenceNumber']),
      description: serializer.fromJson<String>(json['description']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      status: serializer.fromJson<String>(json['status']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      remoteRevision: serializer.fromJson<int?>(json['remoteRevision']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<DateTime?>(json['lastSyncedAt']),
      syncError: serializer.fromJson<String?>(json['syncError']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
      originDeviceId: serializer.fromJson<String>(json['originDeviceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'remoteId': serializer.toJson<String?>(remoteId),
      'companyId': serializer.toJson<String>(companyId),
      'entryDate': serializer.toJson<String>(entryDate),
      'referenceNumber': serializer.toJson<String?>(referenceNumber),
      'description': serializer.toJson<String>(description),
      'sourceType': serializer.toJson<String>(sourceType),
      'status': serializer.toJson<String>(status),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'localRevision': serializer.toJson<int>(localRevision),
      'remoteRevision': serializer.toJson<int?>(remoteRevision),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'lastSyncedAt': serializer.toJson<DateTime?>(lastSyncedAt),
      'syncError': serializer.toJson<String?>(syncError),
      'isDirty': serializer.toJson<bool>(isDirty),
      'originDeviceId': serializer.toJson<String>(originDeviceId),
    };
  }

  JournalEntriesV1Data copyWith({
    String? localId,
    Value<String?> remoteId = const Value.absent(),
    String? companyId,
    String? entryDate,
    Value<String?> referenceNumber = const Value.absent(),
    String? description,
    String? sourceType,
    String? status,
    String? syncStatus,
    int? localRevision,
    Value<int?> remoteRevision = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<DateTime?> lastSyncedAt = const Value.absent(),
    Value<String?> syncError = const Value.absent(),
    bool? isDirty,
    String? originDeviceId,
  }) => JournalEntriesV1Data(
    localId: localId ?? this.localId,
    remoteId: remoteId.present ? remoteId.value : this.remoteId,
    companyId: companyId ?? this.companyId,
    entryDate: entryDate ?? this.entryDate,
    referenceNumber: referenceNumber.present
        ? referenceNumber.value
        : this.referenceNumber,
    description: description ?? this.description,
    sourceType: sourceType ?? this.sourceType,
    status: status ?? this.status,
    syncStatus: syncStatus ?? this.syncStatus,
    localRevision: localRevision ?? this.localRevision,
    remoteRevision: remoteRevision.present
        ? remoteRevision.value
        : this.remoteRevision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
    syncError: syncError.present ? syncError.value : this.syncError,
    isDirty: isDirty ?? this.isDirty,
    originDeviceId: originDeviceId ?? this.originDeviceId,
  );
  JournalEntriesV1Data copyWithCompanion(JournalEntriesV1Companion data) {
    return JournalEntriesV1Data(
      localId: data.localId.present ? data.localId.value : this.localId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      referenceNumber: data.referenceNumber.present
          ? data.referenceNumber.value
          : this.referenceNumber,
      description: data.description.present
          ? data.description.value
          : this.description,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      status: data.status.present ? data.status.value : this.status,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      remoteRevision: data.remoteRevision.present
          ? data.remoteRevision.value
          : this.remoteRevision,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      syncError: data.syncError.present ? data.syncError.value : this.syncError,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesV1Data(')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('companyId: $companyId, ')
          ..write('entryDate: $entryDate, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('description: $description, ')
          ..write('sourceType: $sourceType, ')
          ..write('status: $status, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localRevision: $localRevision, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('syncError: $syncError, ')
          ..write('isDirty: $isDirty, ')
          ..write('originDeviceId: $originDeviceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    remoteId,
    companyId,
    entryDate,
    referenceNumber,
    description,
    sourceType,
    status,
    syncStatus,
    localRevision,
    remoteRevision,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
    syncError,
    isDirty,
    originDeviceId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntriesV1Data &&
          other.localId == this.localId &&
          other.remoteId == this.remoteId &&
          other.companyId == this.companyId &&
          other.entryDate == this.entryDate &&
          other.referenceNumber == this.referenceNumber &&
          other.description == this.description &&
          other.sourceType == this.sourceType &&
          other.status == this.status &&
          other.syncStatus == this.syncStatus &&
          other.localRevision == this.localRevision &&
          other.remoteRevision == this.remoteRevision &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.syncError == this.syncError &&
          other.isDirty == this.isDirty &&
          other.originDeviceId == this.originDeviceId);
}

class JournalEntriesV1Companion extends UpdateCompanion<JournalEntriesV1Data> {
  final Value<String> localId;
  final Value<String?> remoteId;
  final Value<String> companyId;
  final Value<String> entryDate;
  final Value<String?> referenceNumber;
  final Value<String> description;
  final Value<String> sourceType;
  final Value<String> status;
  final Value<String> syncStatus;
  final Value<int> localRevision;
  final Value<int?> remoteRevision;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime?> lastSyncedAt;
  final Value<String?> syncError;
  final Value<bool> isDirty;
  final Value<String> originDeviceId;
  final Value<int> rowid;
  const JournalEntriesV1Companion({
    this.localId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.companyId = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.description = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.status = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.remoteRevision = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.syncError = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalEntriesV1Companion.insert({
    required String localId,
    this.remoteId = const Value.absent(),
    required String companyId,
    required String entryDate,
    this.referenceNumber = const Value.absent(),
    required String description,
    this.sourceType = const Value.absent(),
    this.status = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.remoteRevision = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.syncError = const Value.absent(),
    this.isDirty = const Value.absent(),
    required String originDeviceId,
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       companyId = Value(companyId),
       entryDate = Value(entryDate),
       description = Value(description),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       originDeviceId = Value(originDeviceId);
  static Insertable<JournalEntriesV1Data> custom({
    Expression<String>? localId,
    Expression<String>? remoteId,
    Expression<String>? companyId,
    Expression<String>? entryDate,
    Expression<String>? referenceNumber,
    Expression<String>? description,
    Expression<String>? sourceType,
    Expression<String>? status,
    Expression<String>? syncStatus,
    Expression<int>? localRevision,
    Expression<int>? remoteRevision,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<String>? syncError,
    Expression<bool>? isDirty,
    Expression<String>? originDeviceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (remoteId != null) 'remote_id': remoteId,
      if (companyId != null) 'company_id': companyId,
      if (entryDate != null) 'entry_date': entryDate,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (description != null) 'description': description,
      if (sourceType != null) 'source_type': sourceType,
      if (status != null) 'status': status,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (localRevision != null) 'local_revision': localRevision,
      if (remoteRevision != null) 'remote_revision': remoteRevision,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (syncError != null) 'sync_error': syncError,
      if (isDirty != null) 'is_dirty': isDirty,
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalEntriesV1Companion copyWith({
    Value<String>? localId,
    Value<String?>? remoteId,
    Value<String>? companyId,
    Value<String>? entryDate,
    Value<String?>? referenceNumber,
    Value<String>? description,
    Value<String>? sourceType,
    Value<String>? status,
    Value<String>? syncStatus,
    Value<int>? localRevision,
    Value<int?>? remoteRevision,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime?>? lastSyncedAt,
    Value<String?>? syncError,
    Value<bool>? isDirty,
    Value<String>? originDeviceId,
    Value<int>? rowid,
  }) {
    return JournalEntriesV1Companion(
      localId: localId ?? this.localId,
      remoteId: remoteId ?? this.remoteId,
      companyId: companyId ?? this.companyId,
      entryDate: entryDate ?? this.entryDate,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      description: description ?? this.description,
      sourceType: sourceType ?? this.sourceType,
      status: status ?? this.status,
      syncStatus: syncStatus ?? this.syncStatus,
      localRevision: localRevision ?? this.localRevision,
      remoteRevision: remoteRevision ?? this.remoteRevision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: syncError ?? this.syncError,
      isDirty: isDirty ?? this.isDirty,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (entryDate.present) {
      map['entry_date'] = Variable<String>(entryDate.value);
    }
    if (referenceNumber.present) {
      map['reference_number'] = Variable<String>(referenceNumber.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (remoteRevision.present) {
      map['remote_revision'] = Variable<int>(remoteRevision.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (syncError.present) {
      map['sync_error'] = Variable<String>(syncError.value);
    }
    if (isDirty.present) {
      map['is_dirty'] = Variable<bool>(isDirty.value);
    }
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesV1Companion(')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('companyId: $companyId, ')
          ..write('entryDate: $entryDate, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('description: $description, ')
          ..write('sourceType: $sourceType, ')
          ..write('status: $status, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localRevision: $localRevision, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('syncError: $syncError, ')
          ..write('isDirty: $isDirty, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JournalLinesV1Table extends JournalLinesV1
    with TableInfo<$JournalLinesV1Table, JournalLinesV1Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalLinesV1Table(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _journalLocalIdMeta = const VerificationMeta(
    'journalLocalId',
  );
  @override
  late final GeneratedColumn<String> journalLocalId = GeneratedColumn<String>(
    'journal_local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountCodeMeta = const VerificationMeta(
    'accountCode',
  );
  @override
  late final GeneratedColumn<String> accountCode = GeneratedColumn<String>(
    'account_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountNameMeta = const VerificationMeta(
    'accountName',
  );
  @override
  late final GeneratedColumn<String> accountName = GeneratedColumn<String>(
    'account_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _narrationMeta = const VerificationMeta(
    'narration',
  );
  @override
  late final GeneratedColumn<String> narration = GeneratedColumn<String>(
    'narration',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    journalLocalId,
    accountId,
    accountCode,
    accountName,
    direction,
    amountPaise,
    narration,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalLinesV1Data> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('journal_local_id')) {
      context.handle(
        _journalLocalIdMeta,
        journalLocalId.isAcceptableOrUnknown(
          data['journal_local_id']!,
          _journalLocalIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_journalLocalIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('account_code')) {
      context.handle(
        _accountCodeMeta,
        accountCode.isAcceptableOrUnknown(
          data['account_code']!,
          _accountCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountCodeMeta);
    }
    if (data.containsKey('account_name')) {
      context.handle(
        _accountNameMeta,
        accountName.isAcceptableOrUnknown(
          data['account_name']!,
          _accountNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accountNameMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountPaiseMeta);
    }
    if (data.containsKey('narration')) {
      context.handle(
        _narrationMeta,
        narration.isAcceptableOrUnknown(data['narration']!, _narrationMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  JournalLinesV1Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalLinesV1Data(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      journalLocalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journal_local_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      accountCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_code'],
      )!,
      accountName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_name'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      narration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}narration'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $JournalLinesV1Table createAlias(String alias) {
    return $JournalLinesV1Table(attachedDatabase, alias);
  }
}

class JournalLinesV1Data extends DataClass
    implements Insertable<JournalLinesV1Data> {
  final String localId;
  final String journalLocalId;
  final String accountId;
  final String accountCode;
  final String accountName;
  final String direction;
  final int amountPaise;
  final String? narration;
  final int sortOrder;
  const JournalLinesV1Data({
    required this.localId,
    required this.journalLocalId,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.direction,
    required this.amountPaise,
    this.narration,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    map['journal_local_id'] = Variable<String>(journalLocalId);
    map['account_id'] = Variable<String>(accountId);
    map['account_code'] = Variable<String>(accountCode);
    map['account_name'] = Variable<String>(accountName);
    map['direction'] = Variable<String>(direction);
    map['amount_paise'] = Variable<int>(amountPaise);
    if (!nullToAbsent || narration != null) {
      map['narration'] = Variable<String>(narration);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  JournalLinesV1Companion toCompanion(bool nullToAbsent) {
    return JournalLinesV1Companion(
      localId: Value(localId),
      journalLocalId: Value(journalLocalId),
      accountId: Value(accountId),
      accountCode: Value(accountCode),
      accountName: Value(accountName),
      direction: Value(direction),
      amountPaise: Value(amountPaise),
      narration: narration == null && nullToAbsent
          ? const Value.absent()
          : Value(narration),
      sortOrder: Value(sortOrder),
    );
  }

  factory JournalLinesV1Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalLinesV1Data(
      localId: serializer.fromJson<String>(json['localId']),
      journalLocalId: serializer.fromJson<String>(json['journalLocalId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      accountCode: serializer.fromJson<String>(json['accountCode']),
      accountName: serializer.fromJson<String>(json['accountName']),
      direction: serializer.fromJson<String>(json['direction']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      narration: serializer.fromJson<String?>(json['narration']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'journalLocalId': serializer.toJson<String>(journalLocalId),
      'accountId': serializer.toJson<String>(accountId),
      'accountCode': serializer.toJson<String>(accountCode),
      'accountName': serializer.toJson<String>(accountName),
      'direction': serializer.toJson<String>(direction),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'narration': serializer.toJson<String?>(narration),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  JournalLinesV1Data copyWith({
    String? localId,
    String? journalLocalId,
    String? accountId,
    String? accountCode,
    String? accountName,
    String? direction,
    int? amountPaise,
    Value<String?> narration = const Value.absent(),
    int? sortOrder,
  }) => JournalLinesV1Data(
    localId: localId ?? this.localId,
    journalLocalId: journalLocalId ?? this.journalLocalId,
    accountId: accountId ?? this.accountId,
    accountCode: accountCode ?? this.accountCode,
    accountName: accountName ?? this.accountName,
    direction: direction ?? this.direction,
    amountPaise: amountPaise ?? this.amountPaise,
    narration: narration.present ? narration.value : this.narration,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  JournalLinesV1Data copyWithCompanion(JournalLinesV1Companion data) {
    return JournalLinesV1Data(
      localId: data.localId.present ? data.localId.value : this.localId,
      journalLocalId: data.journalLocalId.present
          ? data.journalLocalId.value
          : this.journalLocalId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      accountCode: data.accountCode.present
          ? data.accountCode.value
          : this.accountCode,
      accountName: data.accountName.present
          ? data.accountName.value
          : this.accountName,
      direction: data.direction.present ? data.direction.value : this.direction,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      narration: data.narration.present ? data.narration.value : this.narration,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalLinesV1Data(')
          ..write('localId: $localId, ')
          ..write('journalLocalId: $journalLocalId, ')
          ..write('accountId: $accountId, ')
          ..write('accountCode: $accountCode, ')
          ..write('accountName: $accountName, ')
          ..write('direction: $direction, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('narration: $narration, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    journalLocalId,
    accountId,
    accountCode,
    accountName,
    direction,
    amountPaise,
    narration,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalLinesV1Data &&
          other.localId == this.localId &&
          other.journalLocalId == this.journalLocalId &&
          other.accountId == this.accountId &&
          other.accountCode == this.accountCode &&
          other.accountName == this.accountName &&
          other.direction == this.direction &&
          other.amountPaise == this.amountPaise &&
          other.narration == this.narration &&
          other.sortOrder == this.sortOrder);
}

class JournalLinesV1Companion extends UpdateCompanion<JournalLinesV1Data> {
  final Value<String> localId;
  final Value<String> journalLocalId;
  final Value<String> accountId;
  final Value<String> accountCode;
  final Value<String> accountName;
  final Value<String> direction;
  final Value<int> amountPaise;
  final Value<String?> narration;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const JournalLinesV1Companion({
    this.localId = const Value.absent(),
    this.journalLocalId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.accountCode = const Value.absent(),
    this.accountName = const Value.absent(),
    this.direction = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.narration = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalLinesV1Companion.insert({
    required String localId,
    required String journalLocalId,
    required String accountId,
    required String accountCode,
    required String accountName,
    required String direction,
    required int amountPaise,
    this.narration = const Value.absent(),
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : localId = Value(localId),
       journalLocalId = Value(journalLocalId),
       accountId = Value(accountId),
       accountCode = Value(accountCode),
       accountName = Value(accountName),
       direction = Value(direction),
       amountPaise = Value(amountPaise),
       sortOrder = Value(sortOrder);
  static Insertable<JournalLinesV1Data> custom({
    Expression<String>? localId,
    Expression<String>? journalLocalId,
    Expression<String>? accountId,
    Expression<String>? accountCode,
    Expression<String>? accountName,
    Expression<String>? direction,
    Expression<int>? amountPaise,
    Expression<String>? narration,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (journalLocalId != null) 'journal_local_id': journalLocalId,
      if (accountId != null) 'account_id': accountId,
      if (accountCode != null) 'account_code': accountCode,
      if (accountName != null) 'account_name': accountName,
      if (direction != null) 'direction': direction,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (narration != null) 'narration': narration,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalLinesV1Companion copyWith({
    Value<String>? localId,
    Value<String>? journalLocalId,
    Value<String>? accountId,
    Value<String>? accountCode,
    Value<String>? accountName,
    Value<String>? direction,
    Value<int>? amountPaise,
    Value<String?>? narration,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return JournalLinesV1Companion(
      localId: localId ?? this.localId,
      journalLocalId: journalLocalId ?? this.journalLocalId,
      accountId: accountId ?? this.accountId,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      direction: direction ?? this.direction,
      amountPaise: amountPaise ?? this.amountPaise,
      narration: narration ?? this.narration,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (journalLocalId.present) {
      map['journal_local_id'] = Variable<String>(journalLocalId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (accountCode.present) {
      map['account_code'] = Variable<String>(accountCode.value);
    }
    if (accountName.present) {
      map['account_name'] = Variable<String>(accountName.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (narration.present) {
      map['narration'] = Variable<String>(narration.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalLinesV1Companion(')
          ..write('localId: $localId, ')
          ..write('journalLocalId: $journalLocalId, ')
          ..write('accountId: $accountId, ')
          ..write('accountCode: $accountCode, ')
          ..write('accountName: $accountName, ')
          ..write('direction: $direction, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('narration: $narration, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOperationsV1Table extends SyncOperationsV1
    with TableInfo<$SyncOperationsV1Table, SyncOperationsV1Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOperationsV1Table(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityLocalIdMeta = const VerificationMeta(
    'entityLocalId',
  );
  @override
  late final GeneratedColumn<String> entityLocalId = GeneratedColumn<String>(
    'entity_local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dependencyIdsMeta = const VerificationMeta(
    'dependencyIds',
  );
  @override
  late final GeneratedColumn<String> dependencyIds = GeneratedColumn<String>(
    'dependency_ids',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityLocalId,
    operationType,
    payload,
    idempotencyKey,
    priority,
    attemptCount,
    nextAttemptAt,
    createdAt,
    startedAt,
    completedAt,
    lastError,
    dependencyIds,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOperationsV1Data> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_local_id')) {
      context.handle(
        _entityLocalIdMeta,
        entityLocalId.isAcceptableOrUnknown(
          data['entity_local_id']!,
          _entityLocalIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityLocalIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('dependency_ids')) {
      context.handle(
        _dependencyIdsMeta,
        dependencyIds.isAcceptableOrUnknown(
          data['dependency_ids']!,
          _dependencyIdsMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOperationsV1Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOperationsV1Data(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityLocalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_local_id'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      dependencyIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dependency_ids'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $SyncOperationsV1Table createAlias(String alias) {
    return $SyncOperationsV1Table(attachedDatabase, alias);
  }
}

class SyncOperationsV1Data extends DataClass
    implements Insertable<SyncOperationsV1Data> {
  final String id;
  final String entityType;
  final String entityLocalId;
  final String operationType;
  final String payload;
  final String idempotencyKey;
  final int priority;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? lastError;
  final String? dependencyIds;
  final String status;
  const SyncOperationsV1Data({
    required this.id,
    required this.entityType,
    required this.entityLocalId,
    required this.operationType,
    required this.payload,
    required this.idempotencyKey,
    required this.priority,
    required this.attemptCount,
    this.nextAttemptAt,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.lastError,
    this.dependencyIds,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_local_id'] = Variable<String>(entityLocalId);
    map['operation_type'] = Variable<String>(operationType);
    map['payload'] = Variable<String>(payload);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['priority'] = Variable<int>(priority);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || dependencyIds != null) {
      map['dependency_ids'] = Variable<String>(dependencyIds);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  SyncOperationsV1Companion toCompanion(bool nullToAbsent) {
    return SyncOperationsV1Companion(
      id: Value(id),
      entityType: Value(entityType),
      entityLocalId: Value(entityLocalId),
      operationType: Value(operationType),
      payload: Value(payload),
      idempotencyKey: Value(idempotencyKey),
      priority: Value(priority),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      createdAt: Value(createdAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      dependencyIds: dependencyIds == null && nullToAbsent
          ? const Value.absent()
          : Value(dependencyIds),
      status: Value(status),
    );
  }

  factory SyncOperationsV1Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOperationsV1Data(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityLocalId: serializer.fromJson<String>(json['entityLocalId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      payload: serializer.fromJson<String>(json['payload']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      priority: serializer.fromJson<int>(json['priority']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      dependencyIds: serializer.fromJson<String?>(json['dependencyIds']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityLocalId': serializer.toJson<String>(entityLocalId),
      'operationType': serializer.toJson<String>(operationType),
      'payload': serializer.toJson<String>(payload),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'priority': serializer.toJson<int>(priority),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'lastError': serializer.toJson<String?>(lastError),
      'dependencyIds': serializer.toJson<String?>(dependencyIds),
      'status': serializer.toJson<String>(status),
    };
  }

  SyncOperationsV1Data copyWith({
    String? id,
    String? entityType,
    String? entityLocalId,
    String? operationType,
    String? payload,
    String? idempotencyKey,
    int? priority,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> startedAt = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<String?> dependencyIds = const Value.absent(),
    String? status,
  }) => SyncOperationsV1Data(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityLocalId: entityLocalId ?? this.entityLocalId,
    operationType: operationType ?? this.operationType,
    payload: payload ?? this.payload,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    priority: priority ?? this.priority,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    createdAt: createdAt ?? this.createdAt,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    dependencyIds: dependencyIds.present
        ? dependencyIds.value
        : this.dependencyIds,
    status: status ?? this.status,
  );
  SyncOperationsV1Data copyWithCompanion(SyncOperationsV1Companion data) {
    return SyncOperationsV1Data(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityLocalId: data.entityLocalId.present
          ? data.entityLocalId.value
          : this.entityLocalId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      payload: data.payload.present ? data.payload.value : this.payload,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      priority: data.priority.present ? data.priority.value : this.priority,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      dependencyIds: data.dependencyIds.present
          ? data.dependencyIds.value
          : this.dependencyIds,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsV1Data(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityLocalId: $entityLocalId, ')
          ..write('operationType: $operationType, ')
          ..write('payload: $payload, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('priority: $priority, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('lastError: $lastError, ')
          ..write('dependencyIds: $dependencyIds, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityLocalId,
    operationType,
    payload,
    idempotencyKey,
    priority,
    attemptCount,
    nextAttemptAt,
    createdAt,
    startedAt,
    completedAt,
    lastError,
    dependencyIds,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOperationsV1Data &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityLocalId == this.entityLocalId &&
          other.operationType == this.operationType &&
          other.payload == this.payload &&
          other.idempotencyKey == this.idempotencyKey &&
          other.priority == this.priority &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.createdAt == this.createdAt &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.lastError == this.lastError &&
          other.dependencyIds == this.dependencyIds &&
          other.status == this.status);
}

class SyncOperationsV1Companion extends UpdateCompanion<SyncOperationsV1Data> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityLocalId;
  final Value<String> operationType;
  final Value<String> payload;
  final Value<String> idempotencyKey;
  final Value<int> priority;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<DateTime> createdAt;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> completedAt;
  final Value<String?> lastError;
  final Value<String?> dependencyIds;
  final Value<String> status;
  final Value<int> rowid;
  const SyncOperationsV1Companion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityLocalId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.payload = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.priority = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.dependencyIds = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOperationsV1Companion.insert({
    required String id,
    required String entityType,
    required String entityLocalId,
    required String operationType,
    required String payload,
    required String idempotencyKey,
    this.priority = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    required DateTime createdAt,
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.dependencyIds = const Value.absent(),
    required String status,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entityType = Value(entityType),
       entityLocalId = Value(entityLocalId),
       operationType = Value(operationType),
       payload = Value(payload),
       idempotencyKey = Value(idempotencyKey),
       createdAt = Value(createdAt),
       status = Value(status);
  static Insertable<SyncOperationsV1Data> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityLocalId,
    Expression<String>? operationType,
    Expression<String>? payload,
    Expression<String>? idempotencyKey,
    Expression<int>? priority,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<String>? lastError,
    Expression<String>? dependencyIds,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityLocalId != null) 'entity_local_id': entityLocalId,
      if (operationType != null) 'operation_type': operationType,
      if (payload != null) 'payload': payload,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (priority != null) 'priority': priority,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (createdAt != null) 'created_at': createdAt,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (lastError != null) 'last_error': lastError,
      if (dependencyIds != null) 'dependency_ids': dependencyIds,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOperationsV1Companion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityLocalId,
    Value<String>? operationType,
    Value<String>? payload,
    Value<String>? idempotencyKey,
    Value<int>? priority,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<DateTime>? createdAt,
    Value<DateTime?>? startedAt,
    Value<DateTime?>? completedAt,
    Value<String?>? lastError,
    Value<String?>? dependencyIds,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return SyncOperationsV1Companion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityLocalId: entityLocalId ?? this.entityLocalId,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      priority: priority ?? this.priority,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      lastError: lastError ?? this.lastError,
      dependencyIds: dependencyIds ?? this.dependencyIds,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityLocalId.present) {
      map['entity_local_id'] = Variable<String>(entityLocalId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (dependencyIds.present) {
      map['dependency_ids'] = Variable<String>(dependencyIds.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsV1Companion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityLocalId: $entityLocalId, ')
          ..write('operationType: $operationType, ')
          ..write('payload: $payload, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('priority: $priority, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('lastError: $lastError, ')
          ..write('dependencyIds: $dependencyIds, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncConflictsV1Table extends SyncConflictsV1
    with TableInfo<$SyncConflictsV1Table, SyncConflictsV1Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncConflictsV1Table(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityLocalIdMeta = const VerificationMeta(
    'entityLocalId',
  );
  @override
  late final GeneratedColumn<String> entityLocalId = GeneratedColumn<String>(
    'entity_local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPayloadMeta = const VerificationMeta(
    'localPayload',
  );
  @override
  late final GeneratedColumn<String> localPayload = GeneratedColumn<String>(
    'local_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remotePayloadMeta = const VerificationMeta(
    'remotePayload',
  );
  @override
  late final GeneratedColumn<String> remotePayload = GeneratedColumn<String>(
    'remote_payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detectedAtMeta = const VerificationMeta(
    'detectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> detectedAt = GeneratedColumn<DateTime>(
    'detected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resolutionMeta = const VerificationMeta(
    'resolution',
  );
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
    'resolution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityLocalId,
    localPayload,
    remotePayload,
    detectedAt,
    resolution,
    resolvedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncConflictsV1Data> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_local_id')) {
      context.handle(
        _entityLocalIdMeta,
        entityLocalId.isAcceptableOrUnknown(
          data['entity_local_id']!,
          _entityLocalIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityLocalIdMeta);
    }
    if (data.containsKey('local_payload')) {
      context.handle(
        _localPayloadMeta,
        localPayload.isAcceptableOrUnknown(
          data['local_payload']!,
          _localPayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localPayloadMeta);
    }
    if (data.containsKey('remote_payload')) {
      context.handle(
        _remotePayloadMeta,
        remotePayload.isAcceptableOrUnknown(
          data['remote_payload']!,
          _remotePayloadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remotePayloadMeta);
    }
    if (data.containsKey('detected_at')) {
      context.handle(
        _detectedAtMeta,
        detectedAt.isAcceptableOrUnknown(data['detected_at']!, _detectedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_detectedAtMeta);
    }
    if (data.containsKey('resolution')) {
      context.handle(
        _resolutionMeta,
        resolution.isAcceptableOrUnknown(data['resolution']!, _resolutionMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncConflictsV1Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncConflictsV1Data(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityLocalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_local_id'],
      )!,
      localPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_payload'],
      )!,
      remotePayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_payload'],
      )!,
      detectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}detected_at'],
      )!,
      resolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at'],
      ),
    );
  }

  @override
  $SyncConflictsV1Table createAlias(String alias) {
    return $SyncConflictsV1Table(attachedDatabase, alias);
  }
}

class SyncConflictsV1Data extends DataClass
    implements Insertable<SyncConflictsV1Data> {
  final String id;
  final String entityType;
  final String entityLocalId;
  final String localPayload;
  final String remotePayload;
  final DateTime detectedAt;
  final String? resolution;
  final DateTime? resolvedAt;
  const SyncConflictsV1Data({
    required this.id,
    required this.entityType,
    required this.entityLocalId,
    required this.localPayload,
    required this.remotePayload,
    required this.detectedAt,
    this.resolution,
    this.resolvedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_local_id'] = Variable<String>(entityLocalId);
    map['local_payload'] = Variable<String>(localPayload);
    map['remote_payload'] = Variable<String>(remotePayload);
    map['detected_at'] = Variable<DateTime>(detectedAt);
    if (!nullToAbsent || resolution != null) {
      map['resolution'] = Variable<String>(resolution);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt);
    }
    return map;
  }

  SyncConflictsV1Companion toCompanion(bool nullToAbsent) {
    return SyncConflictsV1Companion(
      id: Value(id),
      entityType: Value(entityType),
      entityLocalId: Value(entityLocalId),
      localPayload: Value(localPayload),
      remotePayload: Value(remotePayload),
      detectedAt: Value(detectedAt),
      resolution: resolution == null && nullToAbsent
          ? const Value.absent()
          : Value(resolution),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
    );
  }

  factory SyncConflictsV1Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncConflictsV1Data(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityLocalId: serializer.fromJson<String>(json['entityLocalId']),
      localPayload: serializer.fromJson<String>(json['localPayload']),
      remotePayload: serializer.fromJson<String>(json['remotePayload']),
      detectedAt: serializer.fromJson<DateTime>(json['detectedAt']),
      resolution: serializer.fromJson<String?>(json['resolution']),
      resolvedAt: serializer.fromJson<DateTime?>(json['resolvedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityLocalId': serializer.toJson<String>(entityLocalId),
      'localPayload': serializer.toJson<String>(localPayload),
      'remotePayload': serializer.toJson<String>(remotePayload),
      'detectedAt': serializer.toJson<DateTime>(detectedAt),
      'resolution': serializer.toJson<String?>(resolution),
      'resolvedAt': serializer.toJson<DateTime?>(resolvedAt),
    };
  }

  SyncConflictsV1Data copyWith({
    String? id,
    String? entityType,
    String? entityLocalId,
    String? localPayload,
    String? remotePayload,
    DateTime? detectedAt,
    Value<String?> resolution = const Value.absent(),
    Value<DateTime?> resolvedAt = const Value.absent(),
  }) => SyncConflictsV1Data(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityLocalId: entityLocalId ?? this.entityLocalId,
    localPayload: localPayload ?? this.localPayload,
    remotePayload: remotePayload ?? this.remotePayload,
    detectedAt: detectedAt ?? this.detectedAt,
    resolution: resolution.present ? resolution.value : this.resolution,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
  );
  SyncConflictsV1Data copyWithCompanion(SyncConflictsV1Companion data) {
    return SyncConflictsV1Data(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityLocalId: data.entityLocalId.present
          ? data.entityLocalId.value
          : this.entityLocalId,
      localPayload: data.localPayload.present
          ? data.localPayload.value
          : this.localPayload,
      remotePayload: data.remotePayload.present
          ? data.remotePayload.value
          : this.remotePayload,
      detectedAt: data.detectedAt.present
          ? data.detectedAt.value
          : this.detectedAt,
      resolution: data.resolution.present
          ? data.resolution.value
          : this.resolution,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsV1Data(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityLocalId: $entityLocalId, ')
          ..write('localPayload: $localPayload, ')
          ..write('remotePayload: $remotePayload, ')
          ..write('detectedAt: $detectedAt, ')
          ..write('resolution: $resolution, ')
          ..write('resolvedAt: $resolvedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityLocalId,
    localPayload,
    remotePayload,
    detectedAt,
    resolution,
    resolvedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncConflictsV1Data &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityLocalId == this.entityLocalId &&
          other.localPayload == this.localPayload &&
          other.remotePayload == this.remotePayload &&
          other.detectedAt == this.detectedAt &&
          other.resolution == this.resolution &&
          other.resolvedAt == this.resolvedAt);
}

class SyncConflictsV1Companion extends UpdateCompanion<SyncConflictsV1Data> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityLocalId;
  final Value<String> localPayload;
  final Value<String> remotePayload;
  final Value<DateTime> detectedAt;
  final Value<String?> resolution;
  final Value<DateTime?> resolvedAt;
  final Value<int> rowid;
  const SyncConflictsV1Companion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityLocalId = const Value.absent(),
    this.localPayload = const Value.absent(),
    this.remotePayload = const Value.absent(),
    this.detectedAt = const Value.absent(),
    this.resolution = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncConflictsV1Companion.insert({
    required String id,
    required String entityType,
    required String entityLocalId,
    required String localPayload,
    required String remotePayload,
    required DateTime detectedAt,
    this.resolution = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       entityType = Value(entityType),
       entityLocalId = Value(entityLocalId),
       localPayload = Value(localPayload),
       remotePayload = Value(remotePayload),
       detectedAt = Value(detectedAt);
  static Insertable<SyncConflictsV1Data> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityLocalId,
    Expression<String>? localPayload,
    Expression<String>? remotePayload,
    Expression<DateTime>? detectedAt,
    Expression<String>? resolution,
    Expression<DateTime>? resolvedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityLocalId != null) 'entity_local_id': entityLocalId,
      if (localPayload != null) 'local_payload': localPayload,
      if (remotePayload != null) 'remote_payload': remotePayload,
      if (detectedAt != null) 'detected_at': detectedAt,
      if (resolution != null) 'resolution': resolution,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncConflictsV1Companion copyWith({
    Value<String>? id,
    Value<String>? entityType,
    Value<String>? entityLocalId,
    Value<String>? localPayload,
    Value<String>? remotePayload,
    Value<DateTime>? detectedAt,
    Value<String?>? resolution,
    Value<DateTime?>? resolvedAt,
    Value<int>? rowid,
  }) {
    return SyncConflictsV1Companion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityLocalId: entityLocalId ?? this.entityLocalId,
      localPayload: localPayload ?? this.localPayload,
      remotePayload: remotePayload ?? this.remotePayload,
      detectedAt: detectedAt ?? this.detectedAt,
      resolution: resolution ?? this.resolution,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityLocalId.present) {
      map['entity_local_id'] = Variable<String>(entityLocalId.value);
    }
    if (localPayload.present) {
      map['local_payload'] = Variable<String>(localPayload.value);
    }
    if (remotePayload.present) {
      map['remote_payload'] = Variable<String>(remotePayload.value);
    }
    if (detectedAt.present) {
      map['detected_at'] = Variable<DateTime>(detectedAt.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncConflictsV1Companion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityLocalId: $entityLocalId, ')
          ..write('localPayload: $localPayload, ')
          ..write('remotePayload: $remotePayload, ')
          ..write('detectedAt: $detectedAt, ')
          ..write('resolution: $resolution, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCheckpointsV1Table extends SyncCheckpointsV1
    with TableInfo<$SyncCheckpointsV1Table, SyncCheckpointsV1Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCheckpointsV1Table(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastServerSequenceMeta =
      const VerificationMeta('lastServerSequence');
  @override
  late final GeneratedColumn<int> lastServerSequence = GeneratedColumn<int>(
    'last_server_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    companyId,
    entityType,
    lastServerSequence,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCheckpointsV1Data> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('last_server_sequence')) {
      context.handle(
        _lastServerSequenceMeta,
        lastServerSequence.isAcceptableOrUnknown(
          data['last_server_sequence']!,
          _lastServerSequenceMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {companyId, entityType};
  @override
  SyncCheckpointsV1Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCheckpointsV1Data(
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      lastServerSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_server_sequence'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncCheckpointsV1Table createAlias(String alias) {
    return $SyncCheckpointsV1Table(attachedDatabase, alias);
  }
}

class SyncCheckpointsV1Data extends DataClass
    implements Insertable<SyncCheckpointsV1Data> {
  final String companyId;
  final String entityType;
  final int lastServerSequence;
  final DateTime updatedAt;
  const SyncCheckpointsV1Data({
    required this.companyId,
    required this.entityType,
    required this.lastServerSequence,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['company_id'] = Variable<String>(companyId);
    map['entity_type'] = Variable<String>(entityType);
    map['last_server_sequence'] = Variable<int>(lastServerSequence);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncCheckpointsV1Companion toCompanion(bool nullToAbsent) {
    return SyncCheckpointsV1Companion(
      companyId: Value(companyId),
      entityType: Value(entityType),
      lastServerSequence: Value(lastServerSequence),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncCheckpointsV1Data.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCheckpointsV1Data(
      companyId: serializer.fromJson<String>(json['companyId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      lastServerSequence: serializer.fromJson<int>(json['lastServerSequence']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'companyId': serializer.toJson<String>(companyId),
      'entityType': serializer.toJson<String>(entityType),
      'lastServerSequence': serializer.toJson<int>(lastServerSequence),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncCheckpointsV1Data copyWith({
    String? companyId,
    String? entityType,
    int? lastServerSequence,
    DateTime? updatedAt,
  }) => SyncCheckpointsV1Data(
    companyId: companyId ?? this.companyId,
    entityType: entityType ?? this.entityType,
    lastServerSequence: lastServerSequence ?? this.lastServerSequence,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncCheckpointsV1Data copyWithCompanion(SyncCheckpointsV1Companion data) {
    return SyncCheckpointsV1Data(
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      lastServerSequence: data.lastServerSequence.present
          ? data.lastServerSequence.value
          : this.lastServerSequence,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpointsV1Data(')
          ..write('companyId: $companyId, ')
          ..write('entityType: $entityType, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(companyId, entityType, lastServerSequence, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCheckpointsV1Data &&
          other.companyId == this.companyId &&
          other.entityType == this.entityType &&
          other.lastServerSequence == this.lastServerSequence &&
          other.updatedAt == this.updatedAt);
}

class SyncCheckpointsV1Companion
    extends UpdateCompanion<SyncCheckpointsV1Data> {
  final Value<String> companyId;
  final Value<String> entityType;
  final Value<int> lastServerSequence;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncCheckpointsV1Companion({
    this.companyId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCheckpointsV1Companion.insert({
    required String companyId,
    required String entityType,
    this.lastServerSequence = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : companyId = Value(companyId),
       entityType = Value(entityType),
       updatedAt = Value(updatedAt);
  static Insertable<SyncCheckpointsV1Data> custom({
    Expression<String>? companyId,
    Expression<String>? entityType,
    Expression<int>? lastServerSequence,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (companyId != null) 'company_id': companyId,
      if (entityType != null) 'entity_type': entityType,
      if (lastServerSequence != null)
        'last_server_sequence': lastServerSequence,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCheckpointsV1Companion copyWith({
    Value<String>? companyId,
    Value<String>? entityType,
    Value<int>? lastServerSequence,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncCheckpointsV1Companion(
      companyId: companyId ?? this.companyId,
      entityType: entityType ?? this.entityType,
      lastServerSequence: lastServerSequence ?? this.lastServerSequence,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (lastServerSequence.present) {
      map['last_server_sequence'] = Variable<int>(lastServerSequence.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpointsV1Companion(')
          ..write('companyId: $companyId, ')
          ..write('entityType: $entityType, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$V1Database extends GeneratedDatabase {
  _$V1Database(QueryExecutor e) : super(e);
  $V1DatabaseManager get managers => $V1DatabaseManager(this);
  late final $JournalEntriesV1Table journalEntriesV1 = $JournalEntriesV1Table(
    this,
  );
  late final $JournalLinesV1Table journalLinesV1 = $JournalLinesV1Table(this);
  late final $SyncOperationsV1Table syncOperationsV1 = $SyncOperationsV1Table(
    this,
  );
  late final $SyncConflictsV1Table syncConflictsV1 = $SyncConflictsV1Table(
    this,
  );
  late final $SyncCheckpointsV1Table syncCheckpointsV1 =
      $SyncCheckpointsV1Table(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    journalEntriesV1,
    journalLinesV1,
    syncOperationsV1,
    syncConflictsV1,
    syncCheckpointsV1,
  ];
}

typedef $$JournalEntriesV1TableCreateCompanionBuilder =
    JournalEntriesV1Companion Function({
      required String localId,
      Value<String?> remoteId,
      required String companyId,
      required String entryDate,
      Value<String?> referenceNumber,
      required String description,
      Value<String> sourceType,
      Value<String> status,
      Value<String> syncStatus,
      Value<int> localRevision,
      Value<int?> remoteRevision,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime?> lastSyncedAt,
      Value<String?> syncError,
      Value<bool> isDirty,
      required String originDeviceId,
      Value<int> rowid,
    });
typedef $$JournalEntriesV1TableUpdateCompanionBuilder =
    JournalEntriesV1Companion Function({
      Value<String> localId,
      Value<String?> remoteId,
      Value<String> companyId,
      Value<String> entryDate,
      Value<String?> referenceNumber,
      Value<String> description,
      Value<String> sourceType,
      Value<String> status,
      Value<String> syncStatus,
      Value<int> localRevision,
      Value<int?> remoteRevision,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime?> lastSyncedAt,
      Value<String?> syncError,
      Value<bool> isDirty,
      Value<String> originDeviceId,
      Value<int> rowid,
    });

class $$JournalEntriesV1TableFilterComposer
    extends Composer<_$V1Database, $JournalEntriesV1Table> {
  $$JournalEntriesV1TableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JournalEntriesV1TableOrderingComposer
    extends Composer<_$V1Database, $JournalEntriesV1Table> {
  $$JournalEntriesV1TableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JournalEntriesV1TableAnnotationComposer
    extends Composer<_$V1Database, $JournalEntriesV1Table> {
  $$JournalEntriesV1TableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get entryDate =>
      $composableBuilder(column: $table.entryDate, builder: (column) => column);

  GeneratedColumn<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncError =>
      $composableBuilder(column: $table.syncError, builder: (column) => column);

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);

  GeneratedColumn<String> get originDeviceId => $composableBuilder(
    column: $table.originDeviceId,
    builder: (column) => column,
  );
}

class $$JournalEntriesV1TableTableManager
    extends
        RootTableManager<
          _$V1Database,
          $JournalEntriesV1Table,
          JournalEntriesV1Data,
          $$JournalEntriesV1TableFilterComposer,
          $$JournalEntriesV1TableOrderingComposer,
          $$JournalEntriesV1TableAnnotationComposer,
          $$JournalEntriesV1TableCreateCompanionBuilder,
          $$JournalEntriesV1TableUpdateCompanionBuilder,
          (
            JournalEntriesV1Data,
            BaseReferences<
              _$V1Database,
              $JournalEntriesV1Table,
              JournalEntriesV1Data
            >,
          ),
          JournalEntriesV1Data,
          PrefetchHooks Function()
        > {
  $$JournalEntriesV1TableTableManager(
    _$V1Database db,
    $JournalEntriesV1Table table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalEntriesV1TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalEntriesV1TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalEntriesV1TableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> entryDate = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int?> remoteRevision = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<String> originDeviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesV1Companion(
                localId: localId,
                remoteId: remoteId,
                companyId: companyId,
                entryDate: entryDate,
                referenceNumber: referenceNumber,
                description: description,
                sourceType: sourceType,
                status: status,
                syncStatus: syncStatus,
                localRevision: localRevision,
                remoteRevision: remoteRevision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                syncError: syncError,
                isDirty: isDirty,
                originDeviceId: originDeviceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                Value<String?> remoteId = const Value.absent(),
                required String companyId,
                required String entryDate,
                Value<String?> referenceNumber = const Value.absent(),
                required String description,
                Value<String> sourceType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int?> remoteRevision = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                required String originDeviceId,
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesV1Companion.insert(
                localId: localId,
                remoteId: remoteId,
                companyId: companyId,
                entryDate: entryDate,
                referenceNumber: referenceNumber,
                description: description,
                sourceType: sourceType,
                status: status,
                syncStatus: syncStatus,
                localRevision: localRevision,
                remoteRevision: remoteRevision,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                syncError: syncError,
                isDirty: isDirty,
                originDeviceId: originDeviceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JournalEntriesV1TableProcessedTableManager =
    ProcessedTableManager<
      _$V1Database,
      $JournalEntriesV1Table,
      JournalEntriesV1Data,
      $$JournalEntriesV1TableFilterComposer,
      $$JournalEntriesV1TableOrderingComposer,
      $$JournalEntriesV1TableAnnotationComposer,
      $$JournalEntriesV1TableCreateCompanionBuilder,
      $$JournalEntriesV1TableUpdateCompanionBuilder,
      (
        JournalEntriesV1Data,
        BaseReferences<
          _$V1Database,
          $JournalEntriesV1Table,
          JournalEntriesV1Data
        >,
      ),
      JournalEntriesV1Data,
      PrefetchHooks Function()
    >;
typedef $$JournalLinesV1TableCreateCompanionBuilder =
    JournalLinesV1Companion Function({
      required String localId,
      required String journalLocalId,
      required String accountId,
      required String accountCode,
      required String accountName,
      required String direction,
      required int amountPaise,
      Value<String?> narration,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$JournalLinesV1TableUpdateCompanionBuilder =
    JournalLinesV1Companion Function({
      Value<String> localId,
      Value<String> journalLocalId,
      Value<String> accountId,
      Value<String> accountCode,
      Value<String> accountName,
      Value<String> direction,
      Value<int> amountPaise,
      Value<String?> narration,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$JournalLinesV1TableFilterComposer
    extends Composer<_$V1Database, $JournalLinesV1Table> {
  $$JournalLinesV1TableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get journalLocalId => $composableBuilder(
    column: $table.journalLocalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountCode => $composableBuilder(
    column: $table.accountCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountName => $composableBuilder(
    column: $table.accountName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get narration => $composableBuilder(
    column: $table.narration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JournalLinesV1TableOrderingComposer
    extends Composer<_$V1Database, $JournalLinesV1Table> {
  $$JournalLinesV1TableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get journalLocalId => $composableBuilder(
    column: $table.journalLocalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountCode => $composableBuilder(
    column: $table.accountCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountName => $composableBuilder(
    column: $table.accountName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get narration => $composableBuilder(
    column: $table.narration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JournalLinesV1TableAnnotationComposer
    extends Composer<_$V1Database, $JournalLinesV1Table> {
  $$JournalLinesV1TableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get journalLocalId => $composableBuilder(
    column: $table.journalLocalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get accountCode => $composableBuilder(
    column: $table.accountCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountName => $composableBuilder(
    column: $table.accountName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get narration =>
      $composableBuilder(column: $table.narration, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$JournalLinesV1TableTableManager
    extends
        RootTableManager<
          _$V1Database,
          $JournalLinesV1Table,
          JournalLinesV1Data,
          $$JournalLinesV1TableFilterComposer,
          $$JournalLinesV1TableOrderingComposer,
          $$JournalLinesV1TableAnnotationComposer,
          $$JournalLinesV1TableCreateCompanionBuilder,
          $$JournalLinesV1TableUpdateCompanionBuilder,
          (
            JournalLinesV1Data,
            BaseReferences<
              _$V1Database,
              $JournalLinesV1Table,
              JournalLinesV1Data
            >,
          ),
          JournalLinesV1Data,
          PrefetchHooks Function()
        > {
  $$JournalLinesV1TableTableManager(_$V1Database db, $JournalLinesV1Table table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalLinesV1TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalLinesV1TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalLinesV1TableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localId = const Value.absent(),
                Value<String> journalLocalId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> accountCode = const Value.absent(),
                Value<String> accountName = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<String?> narration = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalLinesV1Companion(
                localId: localId,
                journalLocalId: journalLocalId,
                accountId: accountId,
                accountCode: accountCode,
                accountName: accountName,
                direction: direction,
                amountPaise: amountPaise,
                narration: narration,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localId,
                required String journalLocalId,
                required String accountId,
                required String accountCode,
                required String accountName,
                required String direction,
                required int amountPaise,
                Value<String?> narration = const Value.absent(),
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => JournalLinesV1Companion.insert(
                localId: localId,
                journalLocalId: journalLocalId,
                accountId: accountId,
                accountCode: accountCode,
                accountName: accountName,
                direction: direction,
                amountPaise: amountPaise,
                narration: narration,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JournalLinesV1TableProcessedTableManager =
    ProcessedTableManager<
      _$V1Database,
      $JournalLinesV1Table,
      JournalLinesV1Data,
      $$JournalLinesV1TableFilterComposer,
      $$JournalLinesV1TableOrderingComposer,
      $$JournalLinesV1TableAnnotationComposer,
      $$JournalLinesV1TableCreateCompanionBuilder,
      $$JournalLinesV1TableUpdateCompanionBuilder,
      (
        JournalLinesV1Data,
        BaseReferences<_$V1Database, $JournalLinesV1Table, JournalLinesV1Data>,
      ),
      JournalLinesV1Data,
      PrefetchHooks Function()
    >;
typedef $$SyncOperationsV1TableCreateCompanionBuilder =
    SyncOperationsV1Companion Function({
      required String id,
      required String entityType,
      required String entityLocalId,
      required String operationType,
      required String payload,
      required String idempotencyKey,
      Value<int> priority,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      required DateTime createdAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> completedAt,
      Value<String?> lastError,
      Value<String?> dependencyIds,
      required String status,
      Value<int> rowid,
    });
typedef $$SyncOperationsV1TableUpdateCompanionBuilder =
    SyncOperationsV1Companion Function({
      Value<String> id,
      Value<String> entityType,
      Value<String> entityLocalId,
      Value<String> operationType,
      Value<String> payload,
      Value<String> idempotencyKey,
      Value<int> priority,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<DateTime> createdAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> completedAt,
      Value<String?> lastError,
      Value<String?> dependencyIds,
      Value<String> status,
      Value<int> rowid,
    });

class $$SyncOperationsV1TableFilterComposer
    extends Composer<_$V1Database, $SyncOperationsV1Table> {
  $$SyncOperationsV1TableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityLocalId => $composableBuilder(
    column: $table.entityLocalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dependencyIds => $composableBuilder(
    column: $table.dependencyIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOperationsV1TableOrderingComposer
    extends Composer<_$V1Database, $SyncOperationsV1Table> {
  $$SyncOperationsV1TableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityLocalId => $composableBuilder(
    column: $table.entityLocalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependencyIds => $composableBuilder(
    column: $table.dependencyIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOperationsV1TableAnnotationComposer
    extends Composer<_$V1Database, $SyncOperationsV1Table> {
  $$SyncOperationsV1TableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityLocalId => $composableBuilder(
    column: $table.entityLocalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get dependencyIds => $composableBuilder(
    column: $table.dependencyIds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$SyncOperationsV1TableTableManager
    extends
        RootTableManager<
          _$V1Database,
          $SyncOperationsV1Table,
          SyncOperationsV1Data,
          $$SyncOperationsV1TableFilterComposer,
          $$SyncOperationsV1TableOrderingComposer,
          $$SyncOperationsV1TableAnnotationComposer,
          $$SyncOperationsV1TableCreateCompanionBuilder,
          $$SyncOperationsV1TableUpdateCompanionBuilder,
          (
            SyncOperationsV1Data,
            BaseReferences<
              _$V1Database,
              $SyncOperationsV1Table,
              SyncOperationsV1Data
            >,
          ),
          SyncOperationsV1Data,
          PrefetchHooks Function()
        > {
  $$SyncOperationsV1TableTableManager(
    _$V1Database db,
    $SyncOperationsV1Table table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOperationsV1TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOperationsV1TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOperationsV1TableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityLocalId = const Value.absent(),
                Value<String> operationType = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> dependencyIds = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOperationsV1Companion(
                id: id,
                entityType: entityType,
                entityLocalId: entityLocalId,
                operationType: operationType,
                payload: payload,
                idempotencyKey: idempotencyKey,
                priority: priority,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                createdAt: createdAt,
                startedAt: startedAt,
                completedAt: completedAt,
                lastError: lastError,
                dependencyIds: dependencyIds,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entityType,
                required String entityLocalId,
                required String operationType,
                required String payload,
                required String idempotencyKey,
                Value<int> priority = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> dependencyIds = const Value.absent(),
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => SyncOperationsV1Companion.insert(
                id: id,
                entityType: entityType,
                entityLocalId: entityLocalId,
                operationType: operationType,
                payload: payload,
                idempotencyKey: idempotencyKey,
                priority: priority,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                createdAt: createdAt,
                startedAt: startedAt,
                completedAt: completedAt,
                lastError: lastError,
                dependencyIds: dependencyIds,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOperationsV1TableProcessedTableManager =
    ProcessedTableManager<
      _$V1Database,
      $SyncOperationsV1Table,
      SyncOperationsV1Data,
      $$SyncOperationsV1TableFilterComposer,
      $$SyncOperationsV1TableOrderingComposer,
      $$SyncOperationsV1TableAnnotationComposer,
      $$SyncOperationsV1TableCreateCompanionBuilder,
      $$SyncOperationsV1TableUpdateCompanionBuilder,
      (
        SyncOperationsV1Data,
        BaseReferences<
          _$V1Database,
          $SyncOperationsV1Table,
          SyncOperationsV1Data
        >,
      ),
      SyncOperationsV1Data,
      PrefetchHooks Function()
    >;
typedef $$SyncConflictsV1TableCreateCompanionBuilder =
    SyncConflictsV1Companion Function({
      required String id,
      required String entityType,
      required String entityLocalId,
      required String localPayload,
      required String remotePayload,
      required DateTime detectedAt,
      Value<String?> resolution,
      Value<DateTime?> resolvedAt,
      Value<int> rowid,
    });
typedef $$SyncConflictsV1TableUpdateCompanionBuilder =
    SyncConflictsV1Companion Function({
      Value<String> id,
      Value<String> entityType,
      Value<String> entityLocalId,
      Value<String> localPayload,
      Value<String> remotePayload,
      Value<DateTime> detectedAt,
      Value<String?> resolution,
      Value<DateTime?> resolvedAt,
      Value<int> rowid,
    });

class $$SyncConflictsV1TableFilterComposer
    extends Composer<_$V1Database, $SyncConflictsV1Table> {
  $$SyncConflictsV1TableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityLocalId => $composableBuilder(
    column: $table.entityLocalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePayload => $composableBuilder(
    column: $table.remotePayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get detectedAt => $composableBuilder(
    column: $table.detectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncConflictsV1TableOrderingComposer
    extends Composer<_$V1Database, $SyncConflictsV1Table> {
  $$SyncConflictsV1TableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityLocalId => $composableBuilder(
    column: $table.entityLocalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePayload => $composableBuilder(
    column: $table.remotePayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get detectedAt => $composableBuilder(
    column: $table.detectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncConflictsV1TableAnnotationComposer
    extends Composer<_$V1Database, $SyncConflictsV1Table> {
  $$SyncConflictsV1TableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityLocalId => $composableBuilder(
    column: $table.entityLocalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPayload => $composableBuilder(
    column: $table.localPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remotePayload => $composableBuilder(
    column: $table.remotePayload,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get detectedAt => $composableBuilder(
    column: $table.detectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );
}

class $$SyncConflictsV1TableTableManager
    extends
        RootTableManager<
          _$V1Database,
          $SyncConflictsV1Table,
          SyncConflictsV1Data,
          $$SyncConflictsV1TableFilterComposer,
          $$SyncConflictsV1TableOrderingComposer,
          $$SyncConflictsV1TableAnnotationComposer,
          $$SyncConflictsV1TableCreateCompanionBuilder,
          $$SyncConflictsV1TableUpdateCompanionBuilder,
          (
            SyncConflictsV1Data,
            BaseReferences<
              _$V1Database,
              $SyncConflictsV1Table,
              SyncConflictsV1Data
            >,
          ),
          SyncConflictsV1Data,
          PrefetchHooks Function()
        > {
  $$SyncConflictsV1TableTableManager(
    _$V1Database db,
    $SyncConflictsV1Table table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncConflictsV1TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncConflictsV1TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncConflictsV1TableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityLocalId = const Value.absent(),
                Value<String> localPayload = const Value.absent(),
                Value<String> remotePayload = const Value.absent(),
                Value<DateTime> detectedAt = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsV1Companion(
                id: id,
                entityType: entityType,
                entityLocalId: entityLocalId,
                localPayload: localPayload,
                remotePayload: remotePayload,
                detectedAt: detectedAt,
                resolution: resolution,
                resolvedAt: resolvedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String entityType,
                required String entityLocalId,
                required String localPayload,
                required String remotePayload,
                required DateTime detectedAt,
                Value<String?> resolution = const Value.absent(),
                Value<DateTime?> resolvedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncConflictsV1Companion.insert(
                id: id,
                entityType: entityType,
                entityLocalId: entityLocalId,
                localPayload: localPayload,
                remotePayload: remotePayload,
                detectedAt: detectedAt,
                resolution: resolution,
                resolvedAt: resolvedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncConflictsV1TableProcessedTableManager =
    ProcessedTableManager<
      _$V1Database,
      $SyncConflictsV1Table,
      SyncConflictsV1Data,
      $$SyncConflictsV1TableFilterComposer,
      $$SyncConflictsV1TableOrderingComposer,
      $$SyncConflictsV1TableAnnotationComposer,
      $$SyncConflictsV1TableCreateCompanionBuilder,
      $$SyncConflictsV1TableUpdateCompanionBuilder,
      (
        SyncConflictsV1Data,
        BaseReferences<
          _$V1Database,
          $SyncConflictsV1Table,
          SyncConflictsV1Data
        >,
      ),
      SyncConflictsV1Data,
      PrefetchHooks Function()
    >;
typedef $$SyncCheckpointsV1TableCreateCompanionBuilder =
    SyncCheckpointsV1Companion Function({
      required String companyId,
      required String entityType,
      Value<int> lastServerSequence,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SyncCheckpointsV1TableUpdateCompanionBuilder =
    SyncCheckpointsV1Companion Function({
      Value<String> companyId,
      Value<String> entityType,
      Value<int> lastServerSequence,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncCheckpointsV1TableFilterComposer
    extends Composer<_$V1Database, $SyncCheckpointsV1Table> {
  $$SyncCheckpointsV1TableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCheckpointsV1TableOrderingComposer
    extends Composer<_$V1Database, $SyncCheckpointsV1Table> {
  $$SyncCheckpointsV1TableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCheckpointsV1TableAnnotationComposer
    extends Composer<_$V1Database, $SyncCheckpointsV1Table> {
  $$SyncCheckpointsV1TableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncCheckpointsV1TableTableManager
    extends
        RootTableManager<
          _$V1Database,
          $SyncCheckpointsV1Table,
          SyncCheckpointsV1Data,
          $$SyncCheckpointsV1TableFilterComposer,
          $$SyncCheckpointsV1TableOrderingComposer,
          $$SyncCheckpointsV1TableAnnotationComposer,
          $$SyncCheckpointsV1TableCreateCompanionBuilder,
          $$SyncCheckpointsV1TableUpdateCompanionBuilder,
          (
            SyncCheckpointsV1Data,
            BaseReferences<
              _$V1Database,
              $SyncCheckpointsV1Table,
              SyncCheckpointsV1Data
            >,
          ),
          SyncCheckpointsV1Data,
          PrefetchHooks Function()
        > {
  $$SyncCheckpointsV1TableTableManager(
    _$V1Database db,
    $SyncCheckpointsV1Table table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCheckpointsV1TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCheckpointsV1TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCheckpointsV1TableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> companyId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<int> lastServerSequence = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCheckpointsV1Companion(
                companyId: companyId,
                entityType: entityType,
                lastServerSequence: lastServerSequence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String companyId,
                required String entityType,
                Value<int> lastServerSequence = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncCheckpointsV1Companion.insert(
                companyId: companyId,
                entityType: entityType,
                lastServerSequence: lastServerSequence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCheckpointsV1TableProcessedTableManager =
    ProcessedTableManager<
      _$V1Database,
      $SyncCheckpointsV1Table,
      SyncCheckpointsV1Data,
      $$SyncCheckpointsV1TableFilterComposer,
      $$SyncCheckpointsV1TableOrderingComposer,
      $$SyncCheckpointsV1TableAnnotationComposer,
      $$SyncCheckpointsV1TableCreateCompanionBuilder,
      $$SyncCheckpointsV1TableUpdateCompanionBuilder,
      (
        SyncCheckpointsV1Data,
        BaseReferences<
          _$V1Database,
          $SyncCheckpointsV1Table,
          SyncCheckpointsV1Data
        >,
      ),
      SyncCheckpointsV1Data,
      PrefetchHooks Function()
    >;

class $V1DatabaseManager {
  final _$V1Database _db;
  $V1DatabaseManager(this._db);
  $$JournalEntriesV1TableTableManager get journalEntriesV1 =>
      $$JournalEntriesV1TableTableManager(_db, _db.journalEntriesV1);
  $$JournalLinesV1TableTableManager get journalLinesV1 =>
      $$JournalLinesV1TableTableManager(_db, _db.journalLinesV1);
  $$SyncOperationsV1TableTableManager get syncOperationsV1 =>
      $$SyncOperationsV1TableTableManager(_db, _db.syncOperationsV1);
  $$SyncConflictsV1TableTableManager get syncConflictsV1 =>
      $$SyncConflictsV1TableTableManager(_db, _db.syncConflictsV1);
  $$SyncCheckpointsV1TableTableManager get syncCheckpointsV1 =>
      $$SyncCheckpointsV1TableTableManager(_db, _db.syncCheckpointsV1);
}
