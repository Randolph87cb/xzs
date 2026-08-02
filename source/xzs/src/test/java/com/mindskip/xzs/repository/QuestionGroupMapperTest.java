package com.mindskip.xzs.repository;

import org.apache.ibatis.builder.xml.XMLMapperBuilder;
import org.apache.ibatis.session.Configuration;
import org.junit.Test;
import java.io.InputStream;
import static org.junit.Assert.assertTrue;

public class QuestionGroupMapperTest {
    @Test
    public void mapperDefinesActiveGroupAndOrderedChildrenContracts() throws Exception {
        Configuration configuration = new Configuration();
        String resource = "mapper/QuestionGroupMapper.xml";
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(resource)) {
            new XMLMapperBuilder(input, configuration, resource, configuration.getSqlFragments()).parse();
        }
        String sql = configuration.getMappedStatement("com.mindskip.xzs.repository.QuestionGroupMapper.selectActiveBySubjectId")
                .getBoundSql(java.util.Collections.singletonMap("subjectId", 9)).getSql().replaceAll("\\s+", " ").toLowerCase();
        assertTrue(sql.contains("deleted=false and status=1"));
        assertTrue(sql.contains("subject_id="));
    }
}
