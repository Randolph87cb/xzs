package com.mindskip.xzs.domain;

import java.io.Serializable;
import java.util.Date;

public class QuestionGroup implements Serializable {
    private static final long serialVersionUID = 7609213666628311214L;

    private Integer id;
    private Integer groupType;
    private Integer subjectId;
    private Integer gradeLevel;
    private Integer difficult;
    private String knowledgePoint;
    private Integer infoTextContentId;
    private String groupCode;
    private String importBatch;
    private String importSource;
    private Integer importParentOrder;
    private Integer createUser;
    private Integer status;
    private Date createTime;
    private Boolean deleted;

    public Integer getId() { return id; }
    public void setId(Integer id) { this.id = id; }
    public Integer getGroupType() { return groupType; }
    public void setGroupType(Integer groupType) { this.groupType = groupType; }
    public Integer getSubjectId() { return subjectId; }
    public void setSubjectId(Integer subjectId) { this.subjectId = subjectId; }
    public Integer getGradeLevel() { return gradeLevel; }
    public void setGradeLevel(Integer gradeLevel) { this.gradeLevel = gradeLevel; }
    public Integer getDifficult() { return difficult; }
    public void setDifficult(Integer difficult) { this.difficult = difficult; }
    public String getKnowledgePoint() { return knowledgePoint; }
    public void setKnowledgePoint(String knowledgePoint) { this.knowledgePoint = trim(knowledgePoint); }
    public Integer getInfoTextContentId() { return infoTextContentId; }
    public void setInfoTextContentId(Integer infoTextContentId) { this.infoTextContentId = infoTextContentId; }
    public String getGroupCode() { return groupCode; }
    public void setGroupCode(String groupCode) { this.groupCode = trim(groupCode); }
    public String getImportBatch() { return importBatch; }
    public void setImportBatch(String importBatch) { this.importBatch = trim(importBatch); }
    public String getImportSource() { return importSource; }
    public void setImportSource(String importSource) { this.importSource = trim(importSource); }
    public Integer getImportParentOrder() { return importParentOrder; }
    public void setImportParentOrder(Integer importParentOrder) { this.importParentOrder = importParentOrder; }
    public Integer getCreateUser() { return createUser; }
    public void setCreateUser(Integer createUser) { this.createUser = createUser; }
    public Integer getStatus() { return status; }
    public void setStatus(Integer status) { this.status = status; }
    public Date getCreateTime() { return createTime; }
    public void setCreateTime(Date createTime) { this.createTime = createTime; }
    public Boolean getDeleted() { return deleted; }
    public void setDeleted(Boolean deleted) { this.deleted = deleted; }

    private String trim(String value) { return value == null ? null : value.trim(); }
}
