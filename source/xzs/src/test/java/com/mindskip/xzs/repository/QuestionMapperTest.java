package com.mindskip.xzs.repository;

import org.apache.ibatis.builder.xml.XMLMapperBuilder;
import org.apache.ibatis.mapping.BoundSql;
import org.apache.ibatis.mapping.MappedStatement;
import org.apache.ibatis.mapping.ResultMapping;
import org.apache.ibatis.session.Configuration;
import org.junit.Test;

import java.io.InputStream;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

public class QuestionMapperTest {

    @Test
    public void titleContentQueryUsesOneJoinedSelectAndMapsQuestionId() throws Exception {
        Configuration configuration = questionConfiguration();

        MappedStatement statement = configuration.getMappedStatement(
                "com.mindskip.xzs.repository.QuestionMapper.selectTitleContentByQuestionIds");
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("questionIds", Arrays.asList(101, 102));
        BoundSql boundSql = statement.getBoundSql(parameters);
        String sql = boundSql.getSql().replaceAll("\\s+", " ").trim().toLowerCase();

        assertTrue(sql.startsWith("select q.id as question_id, tc.content"));
        assertTrue(sql.contains("left join t_text_content tc on tc.id = q.info_text_content_id"));
        assertTrue(sql.contains("where q.id in ( ? , ? )"));
        assertEquals(2, boundSql.getParameterMappings().size());

        ResultMapping questionIdMapping = statement.getResultMaps().get(0).getResultMappings().stream()
                .filter(mapping -> "questionId".equals(mapping.getProperty()))
                .findFirst()
                .orElseThrow(AssertionError::new);
        assertEquals("question_id", questionIdMapping.getColumn());
        assertEquals(Collections.singletonList("question_id"),
                statement.getResultMaps().get(0).getIdResultMappings().stream()
                        .map(ResultMapping::getColumn)
                        .collect(java.util.stream.Collectors.toList()));
    }

    @Test
    public void ordinaryRandomQueriesExcludeCompositeChildren() throws Exception {
        Configuration configuration = questionConfiguration();
        Map<String, Object> parameters = new HashMap<>();
        parameters.put("subjectId", 9);
        parameters.put("limit", 20);
        String sql = configuration.getMappedStatement("com.mindskip.xzs.repository.QuestionMapper.selectRandomBySubjectId")
                .getBoundSql(parameters).getSql().replaceAll("\\s+", " ").toLowerCase();
        assertTrue(sql.contains("question_group_id is null"));

        parameters.put("knowledgePoint", "CSP-J/程序阅读");
        String knowledgeSql = configuration.getMappedStatement("com.mindskip.xzs.repository.QuestionMapper.selectRandomBySubjectIdAndKnowledgePoint")
                .getBoundSql(parameters).getSql().replaceAll("\\s+", " ").toLowerCase();
        assertTrue(knowledgeSql.contains("question_group_id is null"));
    }

    private Configuration questionConfiguration() throws Exception {
        Configuration configuration = new Configuration();
        String resource = "mapper/QuestionMapper.xml";
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(resource)) {
            XMLMapperBuilder builder = new XMLMapperBuilder(input, configuration, resource, configuration.getSqlFragments());
            builder.parse();
        }
        return configuration;
    }
}
