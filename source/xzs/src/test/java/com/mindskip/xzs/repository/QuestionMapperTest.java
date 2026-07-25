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
        Configuration configuration = new Configuration();
        String resource = "mapper/QuestionMapper.xml";
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(resource)) {
            XMLMapperBuilder builder = new XMLMapperBuilder(
                    input, configuration, resource, configuration.getSqlFragments());
            builder.parse();
        }

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
}
