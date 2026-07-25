package com.mindskip.xzs.repository;

import org.apache.ibatis.builder.xml.XMLMapperBuilder;
import org.apache.ibatis.mapping.BoundSql;
import org.apache.ibatis.mapping.MappedStatement;
import org.apache.ibatis.mapping.ResultMapping;
import org.apache.ibatis.session.Configuration;
import org.junit.Test;

import com.mindskip.xzs.viewmodel.student.exampaper.ExamPaperAnswerPageVM;

import java.io.InputStream;
import java.util.stream.Collectors;

import static org.junit.Assert.assertTrue;

public class ExamPaperAnswerMapperTest {

    @Test
    public void studentPageWithSubjectUsesOneJoinedProjection() throws Exception {
        Configuration configuration = parse("mapper/ExamPaperAnswerMapper.xml");
        MappedStatement statement = configuration.getMappedStatement(
                "com.mindskip.xzs.repository.ExamPaperAnswerMapper.studentPageWithSubject");
        ExamPaperAnswerPageVM request = new ExamPaperAnswerPageVM();
        request.setCreateUser(7);
        request.setSubjectId(2);

        BoundSql boundSql = statement.getBoundSql(request);
        String sql = normalize(boundSql.getSql());

        assertTrue(sql.contains("from t_exam_paper_answer answer left join t_subject subject on subject.id = answer.subject_id"));
        assertTrue(sql.contains("answer.create_user = ?"));
        assertTrue(sql.contains("answer.subject_id = ?"));
        assertTrue(sql.endsWith("order by answer.id desc"));
        assertTrue(statement.getResultMaps().get(0).getResultMappings().stream()
                .map(ResultMapping::getProperty)
                .collect(Collectors.toList())
                .contains("subjectName"));
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
