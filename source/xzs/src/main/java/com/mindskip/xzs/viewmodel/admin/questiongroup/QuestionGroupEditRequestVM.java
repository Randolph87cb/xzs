package com.mindskip.xzs.viewmodel.admin.questiongroup;

import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import org.hibernate.validator.constraints.Range;

import javax.validation.Valid;
import javax.validation.constraints.NotBlank;
import javax.validation.constraints.NotNull;
import java.util.List;

public class QuestionGroupEditRequestVM {
    private Integer id;
    @NotNull private Integer groupType;
    @NotNull private Integer subjectId;
    private Integer gradeLevel;
    @Range(min=1, max=5) private Integer difficult;
    @NotBlank private String knowledgePoint;
    @NotBlank private String title;
    private String groupCode;
    private String importBatch;
    private String importSource;
    private Integer importParentOrder;
    private Integer status;
    @Valid private List<QuestionEditRequestVM> questionItems;

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
    public void setKnowledgePoint(String knowledgePoint) { this.knowledgePoint = knowledgePoint; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getGroupCode() { return groupCode; }
    public void setGroupCode(String groupCode) { this.groupCode = groupCode; }
    public String getImportBatch() { return importBatch; }
    public void setImportBatch(String importBatch) { this.importBatch = importBatch; }
    public String getImportSource() { return importSource; }
    public void setImportSource(String importSource) { this.importSource = importSource; }
    public Integer getImportParentOrder() { return importParentOrder; }
    public void setImportParentOrder(Integer importParentOrder) { this.importParentOrder = importParentOrder; }
    public Integer getStatus() { return status; }
    public void setStatus(Integer status) { this.status = status; }
    public List<QuestionEditRequestVM> getQuestionItems() { return questionItems; }
    public void setQuestionItems(List<QuestionEditRequestVM> questionItems) { this.questionItems = questionItems; }
}
