package com.mindskip.xzs.domain.exam;

import com.mindskip.xzs.domain.Question;
import java.util.List;

public class QuestionSelectionUnit {
    private final String type;
    private final Integer id;
    private final String knowledgePoint;
    private final List<Question> questions;

    public QuestionSelectionUnit(String type, Integer id, String knowledgePoint, List<Question> questions) {
        this.type = type;
        this.id = id;
        this.knowledgePoint = knowledgePoint;
        this.questions = questions;
    }

    public String getType() { return type; }
    public Integer getId() { return id; }
    public String getKnowledgePoint() { return knowledgePoint; }
    public List<Question> getQuestions() { return questions; }
    public int getQuestionCount() { return questions.size(); }
}
