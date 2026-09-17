package dev.aeris.companion
import org.junit.Assert.*
import org.junit.Test
class PomodoroTest {
    @Test fun countdownUsesReceiptAgeWithoutInventingTransitions() {
        assertEquals(117L,displayedSeconds(120,3500,true))
        assertEquals(120L,displayedSeconds(120,3500,false))
        assertEquals(120L,displayedSeconds(120,-1000,true))
        assertEquals(0L,displayedSeconds(2,9000,true))
    }
    @Test fun actualRepsAndBothSidesAreRequiredAndOptionalFieldsStayOptional() {
        assertNotNull(validateSetInput("","","","",false))
        assertNotNull(validateSetInput("10","","","",true))
        assertNull(validateSetInput("10","9","","",true))
        assertNull(validateSetInput("10","","6.5","3",false))
        for(load in listOf("NaN","Infinity","-1","501")) assertNotNull(validateSetInput("10","",load,"",false))
        assertNotNull(validateSetInput("10","","6","11",false))
        assertNotNull(validateSetInput("1.5","","","",false))
    }
}
