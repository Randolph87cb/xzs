package com.mindskip.xzs.domain.exam;

public class ExamPaperQuestionItemObject {
    private Integer id;
    private Integer itemOrder;
    private Integer groupItemOrder;

    public Integer getId() {
        return id;
    }

    public void setId(Integer id) {
        this.id = id;
    }

    public Integer getItemOrder() {
        return itemOrder;
    }

    public void setItemOrder(Integer itemOrder) {
        this.itemOrder = itemOrder;
    }

    public Integer getGroupItemOrder() { return groupItemOrder; }
    public void setGroupItemOrder(Integer groupItemOrder) { this.groupItemOrder = groupItemOrder; }
}
