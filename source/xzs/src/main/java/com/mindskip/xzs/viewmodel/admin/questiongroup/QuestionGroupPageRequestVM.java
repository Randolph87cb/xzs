package com.mindskip.xzs.viewmodel.admin.questiongroup;

import com.mindskip.xzs.base.BasePage;

public class QuestionGroupPageRequestVM extends BasePage {
    private Integer id;
    private Integer subjectId;
    private Integer groupType;
    private String knowledgePoint;
    private Integer status;

    public Integer getId() { return id; }
    public void setId(Integer id) { this.id = id; }
    public Integer getSubjectId() { return subjectId; }
    public void setSubjectId(Integer subjectId) { this.subjectId = subjectId; }
    public Integer getGroupType() { return groupType; }
    public void setGroupType(Integer groupType) { this.groupType = groupType; }
    public String getKnowledgePoint() { return knowledgePoint; }
    public void setKnowledgePoint(String knowledgePoint) { this.knowledgePoint = knowledgePoint; }
    public Integer getStatus() { return status; }
    public void setStatus(Integer status) { this.status = status; }
}
