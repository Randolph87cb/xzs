package com.mindskip.xzs.repository;

import org.apache.ibatis.builder.xml.XMLMapperBuilder;
import org.apache.ibatis.mapping.BoundSql;
import org.apache.ibatis.mapping.MappedStatement;
import org.apache.ibatis.mapping.ResultMapping;
import org.apache.ibatis.session.Configuration;
import org.junit.Test;

import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.stream.Collectors;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class ExamPaperQuestionCustomerAnswerMapperTest {

    @Test
    public void workspaceProjectionEnforcesOwnershipAndLoadsSingleRowDependencies() throws Exception {
        Configuration configuration = parse("mapper/ExamPaperQuestionCustomerAnswerMapper.xml");
        MappedStatement statement = configuration.getMappedStatement(
                "com.mindskip.xzs.repository.ExamPaperQuestionCustomerAnswerMapper.selectWrongQuestionWorkspace");
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("customerAnswerId", 13);
        parameters.put("userId", 7);

        BoundSql boundSql = statement.getBoundSql(parameters);
        String sql = normalize(boundSql.getSql());

        assertTrue(sql.contains("answer.id = ?"));
        assertTrue(sql.contains("answer.create_user = ?"));
        assertTrue(sql.contains("answer.do_right = false"));
        assertTrue(sql.contains("inner join t_question question on question.id = answer.question_id"));
        assertTrue(sql.contains("inner join t_text_content question_text on question_text.id = question.info_text_content_id"));
        assertTrue(sql.contains("left join t_text_content answer_text on answer_text.id = answer.text_content_id"));
        assertTrue(sql.contains("left join lateral"));
        assertTrue(sql.contains("customer_answer_id = answer.id"));
        assertTrue(sql.contains("user_id = ?"));
        assertFalse(sql.contains("join t_exam_paper_answer"));

        java.util.List<String> properties = statement.getResultMaps().get(0).getResultMappings().stream()
                .map(ResultMapping::getProperty)
                .collect(Collectors.toList());
        assertTrue(properties.contains("customerAnswer"));
        assertTrue(properties.contains("question"));
        assertTrue(properties.contains("questionContent"));
        assertTrue(properties.contains("answerContent"));
        assertTrue(properties.contains("correction"));
    }

    private Configuration parse(String resource) throws Exception {
        Configuration configuration = new Configuration();
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(resource)) {
            new XMLMapperBuilder(input, configuration, resource, configuration.getSqlFragments()).parse();
        }
        return configuration;
    }

    private String normalize(String sql) {
        return sql.replaceAll("\\s+", " ").trim().toLowerCase();
    }
}
