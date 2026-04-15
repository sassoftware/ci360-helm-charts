CREATE TABLE IF NOT EXISTS contactresponse.contact_history_attributes
(
    contact_history_attributes_sk character varying(36) COLLATE pg_catalog."default" NOT NULL,
    decision_contact_history_sk character varying(36) COLLATE pg_catalog."default",
    key character varying(500) COLLATE pg_catalog."default" NOT NULL,
    val character varying(4000) COLLATE pg_catalog."default",
    creation_dttm timestamp without time zone,
    modified_dttm timestamp without time zone,
    CONSTRAINT contact_history_attributes_pkey PRIMARY KEY (contact_history_attributes_sk)
)

CREATE INDEX IF NOT EXISTS cha_decision_contact_history_sk
    ON contactresponse.contact_history_attributes USING btree
    (decision_contact_history_sk COLLATE pg_catalog."default" ASC NULLS LAST)
    TABLESPACE pg_default;
	
CREATE TABLE IF NOT EXISTS contactresponse.decision_contact_history
(
    decision_contact_history_sk character varying(36) COLLATE pg_catalog."default" NOT NULL,
    identity_value character varying(500) COLLATE pg_catalog."default" NOT NULL,
    identity_type character varying(36) COLLATE pg_catalog."default" DEFAULT 'customer_id',
    subject_level character varying(100) COLLATE pg_catalog."default",
    creation_dttm timestamp without time zone,
    modified_dttm timestamp without time zone,
    channel_nm character varying(250) COLLATE pg_catalog."default",
    response_tracking_cd character varying(36) COLLATE pg_catalog."default",
    decision_id character varying(36) COLLATE pg_catalog."default",
    action_id character varying(36) COLLATE pg_catalog."default",
    action_group_id character varying(36) COLLATE pg_catalog."default",
    action_code character varying(250) COLLATE pg_catalog."default",
    action_category character varying(1024) COLLATE pg_catalog."default",
	action_type character varying(1024) COLLATE pg_catalog."default",
    action_version_no character varying(36) COLLATE pg_catalog."default",
    decision_version_no character varying(36) COLLATE pg_catalog."default",
    CONSTRAINT decision_contact_history_pkey PRIMARY KEY (decision_contact_history_sk)
)

CREATE INDEX IF NOT EXISTS dch_response_tracking_cd
    ON contactresponse.decision_contact_history USING btree
    (response_tracking_cd COLLATE pg_catalog."default" ASC NULLS LAST)
    TABLESPACE pg_default;
	
CREATE TABLE IF NOT EXISTS contactresponse.presented_contact_history
(
    presented_contact_history_sk character varying(36) COLLATE pg_catalog."default" NOT NULL,
    decision_contact_history_sk character varying(36) COLLATE pg_catalog."default",
    presented_txt character varying(1024) COLLATE pg_catalog."default",
    presentation_dttm timestamp without time zone,
    creation_dttm timestamp without time zone,
    modified_dttm timestamp without time zone,
    CONSTRAINT presented_contact_history_pkey PRIMARY KEY (presented_contact_history_sk)
)

CREATE INDEX IF NOT EXISTS pch_decision_contact_history_sk
    ON contactresponse.presented_contact_history USING btree
    (decision_contact_history_sk COLLATE pg_catalog."default" ASC NULLS LAST)
    TABLESPACE pg_default;	
	
CREATE TABLE IF NOT EXISTS contactresponse.response_history
(
    response_history_sk character varying(36) COLLATE pg_catalog."default" NOT NULL,
    response_dttm timestamp without time zone,
    response_txt character varying(1024) COLLATE pg_catalog."default",
    response_type_txt character varying(250) COLLATE pg_catalog."default",
    response_channel character varying(250) COLLATE pg_catalog."default",    
    response_tracking_cd character varying(36) COLLATE pg_catalog."default" NOT NULL,
	response_type_code character varying(250) COLLATE pg_catalog."default" NOT NULL,
	creation_dttm timestamp without time zone,
    CONSTRAINT response_history_pkey PRIMARY KEY (response_history_sk)
)

CREATE INDEX IF NOT EXISTS rh_response_tracking_cd
    ON contactresponse.response_history USING btree
    (response_tracking_cd COLLATE pg_catalog."default" ASC NULLS LAST, decision_contact_history_sk COLLATE pg_catalog."default" ASC NULLS LAST)
    TABLESPACE pg_default;	


CREATE INDEX IF NOT EXISTS idx_contact_history_action_code
    ON contactresponse.decision_contact_history USING btree
    (action_code COLLATE pg_catalog."default" ASC NULLS LAST)
	TABLESPACE pg_default;
	
