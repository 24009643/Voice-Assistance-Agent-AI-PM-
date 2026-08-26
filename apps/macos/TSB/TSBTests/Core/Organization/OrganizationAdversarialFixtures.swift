enum OrganizationAdversarialFixtures {
    static let requestID = "00000000-0000-0000-0000-000000000101"
    static let sourceTextHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    static let meaningReversalSource = "不要上传音频。"
    static let inventedFactSource = "整理当前想法。"

    static let validMixedLanguage = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","no_result_reason":null,"numbered_points":[{"number":1,"text":"今天先完成 TSB 0.2 privacy check。","source_segment_ids":["c1"]},{"number":2,"text":"跟住用廣東話驗證，唔好改原意。","source_segment_ids":["c2"]},{"number":3,"text":"Finally, keep the original meaning.","source_segment_ids":["c3"]}],"known_record_links":[{"candidate_id":"h1","reason":"同一验收主题","source_segment_ids":["c1"]}],"speculative_connections":[{"statement":"可能需要补充人工复核","why_speculative":"尚未由当前文本确认","source_segment_ids":["c2"],"candidate_ids":["h1"]}]}
    """#

    static let meaningReversal = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","no_result_reason":null,"numbered_points":[{"number":1,"text":"上传音频。","source_segment_ids":["c1"]}],"known_record_links":[],"speculative_connections":[]}
    """#

    static let inventedFact = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","no_result_reason":null,"numbered_points":[{"number":1,"text":"用户已经批准把完整历史发送到云端。","source_segment_ids":["c1"]}],"known_record_links":[],"speculative_connections":[]}
    """#

    static let unknownCandidate = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","no_result_reason":null,"numbered_points":[{"number":1,"text":"当前要点","source_segment_ids":["c1"]}],"known_record_links":[{"candidate_id":"h9","reason":"不存在的候选","source_segment_ids":["c1"]}],"speculative_connections":[]}
    """#

    static let unknownCurrentSegment = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","no_result_reason":null,"numbered_points":[{"number":1,"text":"引用不存在的片段","source_segment_ids":["c9"]}],"known_record_links":[],"speculative_connections":[]}
    """#

    static let knownSpeculativeMixing = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","no_result_reason":null,"numbered_points":[{"number":1,"text":"当前要点","source_segment_ids":["c1"]}],"known_record_links":[{"candidate_id":"h1","reason":"已知关联混入推测字段","why_speculative":"未确认","source_segment_ids":["c1"]}],"speculative_connections":[]}
    """#

    static let malformed = #"{"schema_version":"tsb.organization.output.v1","numbered_points":["#

    static let empty = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","no_result_reason":"no_reliable_structure","numbered_points":[],"known_record_links":[],"speculative_connections":[]}
    """#

    static let timeoutLateCallbackOutput = #"""
    {"schema_version":"tsb.organization.output.v1","request_id":"00000000-0000-0000-0000-000000000101","source_text_hash":"bbfb79e82216bd2db1ad2c507d44ddf80aeb12f64f9562056afe93aad43154d9","no_result_reason":null,"numbered_points":[{"number":1,"text":"alpha","source_segment_ids":["c1"]},{"number":2,"text":"beta","source_segment_ids":["c2"]}],"known_record_links":[],"speculative_connections":[]}
    """#
}
